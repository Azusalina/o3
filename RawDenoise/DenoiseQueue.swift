import Foundation
import Observation
import UIKit

struct QueueItem: Identifiable {
    let id = UUID()
    let source: URL
    let name: String
    var status = "Queued"
    var progress: Double?
    var output: URL?
    var pending = true
}

@MainActor @Observable
final class DenoiseQueue {
    var items: [QueueItem] = []
    var isRunning = false
    var isImporting = false
    var importStatus = ""
    var importProgress: Double = 0
    var message: String?
    var outputFolder: URL?
    var exportFormat: ExportFormat = .dng
    private var work: Task<Void, Never>?
    private var importWork: Task<Void, Never>?
    private let engine = RawDenoiser()
    private let staging = FileManager.default.temporaryDirectory.appendingPathComponent("RAW-imports", isDirectory: true)

    var hasPending: Bool { items.contains(where: \.pending) }

    init() {
        do {
            let folder = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("denoised", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            outputFolder = folder
            // Imports are transient; exported images survive relaunches.
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch { message = error.localizedDescription }
    }

    func importFiles(_ urls: [URL]) {
        guard !isRunning, !isImporting else { return }
        isImporting = true
        let directory = staging
        importWork = Task {
            defer { isImporting = false; importWork = nil; importStatus = "" }
            var failures: [String] = []
            for (index, url) in urls.enumerated() {
                if Task.isCancelled { break }
                importStatus = "Importing \(index + 1) of \(urls.count): \(url.lastPathComponent)"
                importProgress = 0
                do {
                    let local = try await RawFileImporter.copy(source: url, directory: directory) { value in
                        Task { @MainActor [weak self] in
                            guard let self, self.isImporting else { return }
                            self.importProgress = value
                        }
                    }
                    items.append(QueueItem(source: local, name: url.lastPathComponent))
                } catch is CancellationError { break }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            if !failures.isEmpty { message = failures.joined(separator: "\n\n") }
        }
    }

    func start() {
        guard !isRunning, !isImporting, hasPending, let folder = outputFolder else { return }
        isRunning = true
        let format = exportFormat
        UIApplication.shared.isIdleTimerDisabled = true
        work = Task {
            defer {
                isRunning = false
                UIApplication.shared.isIdleTimerDisabled = false
                work = nil
            }
            for index in items.indices where items[index].pending {
                if Task.isCancelled { break }
                let item = items[index]
                items[index].status = "Decoding RAW…"
                items[index].progress = 0
                do {
                    let output = try await engine.denoise(source: item.source, name: item.name, folder: folder, format: format) { value in
                        Task { @MainActor [weak self] in
                            guard let self, self.isRunning,
                                  let row = self.items.firstIndex(where: { $0.id == item.id }),
                                  self.items[row].progress != nil else { return }
                            self.items[row].status = value < 1 ? "Denoising" : "Saving \(format.label)…"
                            self.items[row].progress = value
                        }
                    }
                    items[index].output = output
                    items[index].status = "Saved · \(output.lastPathComponent)"
                    items[index].pending = false
                    try? FileManager.default.removeItem(at: item.source)
                } catch is CancellationError {
                    items[index].status = "Cancelled · ready to retry"
                    items[index].progress = nil
                    break
                } catch {
                    items[index].status = "Failed · \(error.localizedDescription)"
                    items[index].pending = false
                }
                items[index].progress = nil
            }
        }
    }

    func cancel() { work?.cancel(); importWork?.cancel() }

    func clear() {
        guard !isRunning, !isImporting else { return }
        for item in items { try? FileManager.default.removeItem(at: item.source) }
        items.removeAll()
    }
}
