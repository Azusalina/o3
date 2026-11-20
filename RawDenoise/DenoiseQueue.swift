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
    var message: String?
    var outputFolder: URL?
    private var work: Task<Void, Never>?
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
        Task {
            for url in urls {
                do {
                    // Await the copy before processing another input; never load a whole batch in memory.
                    let local = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let destination = directory.appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension)
                        let coordinator = NSFileCoordinator()
                        var coordinationError: NSError?
                        var copyError: Error?
                        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                            do { try FileManager.default.copyItem(at: readable, to: destination) }
                            catch { copyError = error }
                        }
                        if let error = coordinationError { throw error }
                        if let error = copyError { throw error }
                        return destination
                    }.value
                    items.append(QueueItem(source: local, name: url.lastPathComponent))
                } catch { message = "Could not import \(url.lastPathComponent): \(error.localizedDescription)" }
            }
            isImporting = false
        }
    }

    func start() {
        guard !isRunning, !isImporting, hasPending, let folder = outputFolder else { return }
        isRunning = true
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
                    let output = try await engine.denoise(source: item.source, name: item.name, folder: folder) { value in
                        Task { @MainActor [weak self] in
                            guard let self, self.isRunning,
                                  let row = self.items.firstIndex(where: { $0.id == item.id }),
                                  self.items[row].progress != nil else { return }
                            self.items[row].status = value < 1 ? "Denoising" : "Saving TIFF…"
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

    func cancel() { work?.cancel() }

    func clear() {
        guard !isRunning, !isImporting else { return }
        for item in items { try? FileManager.default.removeItem(at: item.source) }
        items.removeAll()
    }
}
