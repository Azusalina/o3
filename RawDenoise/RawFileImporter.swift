import Foundation
import UniformTypeIdentifiers

enum RawFileImporter {
    enum ImportError: LocalizedError {
        case notRAW, emptyFile, cannotCreate
        var errorDescription: String? {
            switch self {
            case .notRAW: "Select a RAW image such as DNG, CR3, CR2, NEF, ARW, or RAF."
            case .emptyFile: "This file is empty. Download the original in Files and try again."
            case .cannotCreate: "Cannot save the imported file. Check available storage."
            }
        }
    }

    static func supports(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let cameraExtensions: Set<String> = ["dng", "raw", "cr2", "cr3", "crw", "nef", "nrw",
            "arw", "srf", "sr2", "raf", "rw2", "rwl", "orf", "ori", "pef", "ptx", "srw",
            "3fr", "fff", "iiq", "mos", "kdc", "dcr", "erf", "mrw", "x3f", "bay"]
        return cameraExtensions.contains(ext) || UTType(filenameExtension: ext)?.conforms(to: .rawImage) == true
    }

    /// Source is a local copy delivered by UIDocumentPicker's import mode.
    static func copy(source: URL, directory: URL,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard supports(source) else { throw ImportError.notRAW }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            let size = try input.seekToEnd()
            guard size > 0 else { throw ImportError.emptyFile }
            try input.seek(toOffset: 0)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw ImportError.cannotCreate }
            var completed = false
            defer { if !completed { try? FileManager.default.removeItem(at: destination) } }
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            var copied: UInt64 = 0
            progress(0)
            while true {
                try Task.checkCancellation()
                guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { break }
                try output.write(contentsOf: data)
                copied += UInt64(data.count)
                progress(min(1, Double(copied) / Double(size)))
            }
            try Task.checkCancellation()
            guard copied == size else { throw CocoaError(.fileReadCorruptFile) }
            try output.synchronize()
            completed = true
            return destination
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
