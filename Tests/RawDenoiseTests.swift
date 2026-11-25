import XCTest
import CoreML
import CoreGraphics
import CoreImage
import ImageIO
import UIKit
@testable import RawDenoise

final class RawDenoiseTests: XCTestCase {
    @MainActor
    func testPickerUsesSystemCopiesAndAllowsBatchSelection() {
        var selection: [URL] = []
        var cancelled = false
        let view = RAWFilePicker(onSelection: { selection = $0 }, onCancel: { cancelled = true })
        // Check the same factory used by the presented sheet.
        let coordinator = view.makeCoordinator()
        let configured = view.makePicker(delegate: coordinator)
        XCTAssertEqual(configured.documentPickerMode, .import)
        XCTAssertTrue(configured.allowsMultipleSelection)
        let file = URL(fileURLWithPath: "/tmp/camera.dng")
        coordinator.documentPicker(configured, didPickDocumentsAt: [file])
        XCTAssertEqual(selection, [file])
        coordinator.documentPickerWasCancelled(configured)
        XCTAssertTrue(cancelled)
    }

    func testImportCopiesLargeRAWAndKeepsOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("camera.CR3")
        let bytes = Data(repeating: 123, count: 2_500_000)
        try bytes.write(to: source)
        let copied = try await RawFileImporter.copy(source: source, directory: directory.appendingPathComponent("imports"), progress: { _ in })
        XCTAssertNotEqual(source, copied)
        XCTAssertEqual(copied.pathExtension, "CR3")
        XCTAssertEqual(try Data(contentsOf: copied), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testImportRejectsEmptyAndNonRAWFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["empty.dng", "photo.jpg"] {
            let source = directory.appendingPathComponent(name)
            try Data().write(to: source)
            do {
                _ = try await RawFileImporter.copy(source: source, directory: directory.appendingPathComponent("imports"), progress: { _ in })
                XCTFail("Invalid input should fail")
            } catch is RawFileImporter.ImportError {} catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testCancelledImportCreatesNoPartialFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await RawFileImporter.copy(source: directory.appendingPathComponent("sample.dng"), directory: directory, progress: { _ in })
        }
        do { _ = try await task.value; XCTFail("Cancelled import should fail") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDNGIsRecognizedByAppleRAWDecoder() async throws {
        let width = 512, height = 513
        let raster = try MappedRaster(width: width, height: height)
        for index in 0..<(width * height * 3) { raster.pixels[index] = UInt16(10000 + index % 2000) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dng")
        defer { try? FileManager.default.removeItem(at: url) }
        try withExtendedLifetime(raster) {
            try LinearDNGWriter.write(to: url, width: width, height: height,
                                     pixels: UnsafePointer(raster.pixels), originalName: "sample.dng")
        }
        let importedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: importedDirectory) }
        let copied = try await RawFileImporter.copy(source: url, directory: importedDirectory, progress: { _ in })
        let raw = try XCTUnwrap(CIRAWFilter(imageURL: copied))
        let image = try XCTUnwrap(raw.outputImage)
        XCTAssertEqual(image.extent.width, CGFloat(width))
        XCTAssertEqual(image.extent.height, CGFloat(height))
        let context = CIContext()
        XCTAssertNotNil(context.createCGImage(image, from: image.extent))
    }

    func testTilesCoverEdgesAndNormalize() {
        for length in [1, 63, 255, 256, 257, 448, 449, 512, 601, 6048] {
            let origins = TileLayout.origins(length: length)
            XCTAssertEqual(origins.first, 0)
            XCTAssertEqual(origins.last, max(0, length - 256))
            XCTAssertEqual(Set(origins).count, origins.count)
            let norm = TileLayout.normalization(length: length, origins: origins)
            var reconstructed = [Float](repeating: 0, count: length)
            for origin in origins {
                for offset in 0..<min(256, length - origin) {
                    let index = origin + offset
                    reconstructed[index] += TileLayout.weight(offset) / norm[index]
                }
            }
            for value in reconstructed { XCTAssertEqual(value, 1, accuracy: 0.00001) }
        }
    }

    func testTIFFIsSixteenBitAndKeepsRows() throws {
        let raster = try MappedRaster(width: 2, height: 2)
        // Red top row, blue bottom row: detects row inversion and channel/byte-order errors.
        let pixels: [UInt16] = [65535, 0, 0, 65535, 0, 0, 0, 0, 65535, 0, 0, 65535]
        for index in pixels.indices { raster.pixels[index] = pixels[index] }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        try raster.writeTIFF(to: url, colorSpace: CGColorSpace(name: CGColorSpace.linearITUR_2020)!)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.bitsPerComponent, 16)
        var bytes = [UInt8](repeating: 0, count: 16)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 2, height: 2,
                bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        XCTAssertGreaterThan(bytes[0], 240)
        XCTAssertLessThan(bytes[2], 15)
        XCTAssertLessThan(bytes[8], 15)
        XCTAssertGreaterThan(bytes[10], 240)
    }

    func testBundledModelRunsThroughCoreML() throws { try checkModel(.superLight) }
    func testGeneralModelMatchesUpstream() throws { try checkModel(.general) }
    func testLightModelMatchesUpstream() throws { try checkModel(.light) }
    func testHeavyModelMatchesUpstream() throws { try checkModel(.heavy) }

    private func checkModel(_ selection: DenoiseModel) throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: selection.resourceName, withExtension: "mlmodelc"))
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: url, configuration: config)
        let image = try MLMultiArray(shape: [1, 3, 256, 256], dataType: .float32)
        let ptr = image.dataPointer.assumingMemoryBound(to: Float.self)
        for index in 0..<image.count { ptr[index] = Float((index * 37) % 251) / 1000 }
        let condition = try MLMultiArray(shape: [1, 1], dataType: .float32)
        condition[0] = 1
        let features = try MLDictionaryFeatureProvider(dictionary: ["image": image, "conditioning": condition])
        let result = try model.prediction(from: features)
        let output = try XCTUnwrap(result.featureValue(for: "denoised")?.multiArrayValue)
        XCTAssertEqual(output.shape.map(\.intValue), [1, 3, 256, 256])
        let referenceName = selection == .superLight ? "rawforge" : selection.rawValue
        let referenceURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: referenceName + "-reference", withExtension: "f32"))
        let reference = try Data(contentsOf: referenceURL)
        XCTAssertEqual(reference.count, output.count * 4)
        var maxError: Float = 0
        for index in 0..<output.count {
            let value = output[index].floatValue
            XCTAssertTrue(value.isFinite && value >= 0 && value <= 1)
            let expected = reference.withUnsafeBytes { bytes in
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
            }
            maxError = max(maxError, abs(value - expected))
        }
        XCTAssertLessThan(maxError, 0.002, "\(selection.label) Core ML must match upstream PyTorch")
    }

    func testCancelledProcessingWritesNothing() async throws {
        let engine = RawDenoiser()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.denoise(source: URL(fileURLWithPath: "/missing.dng"), name: "missing.dng",
                folder: FileManager.default.temporaryDirectory, progress: { _ in })
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled task must throw")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
