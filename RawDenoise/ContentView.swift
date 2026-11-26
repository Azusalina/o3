import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var queue = DenoiseQueue()
    @State private var selecting = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Select RAW files", systemImage: "plus") { selecting = true }
                        .disabled(queue.isRunning || queue.isImporting)
                    Text("Select several files at once. Each image is denoised separately on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Denoising") {
                    Picker("TreeNet model", selection: $queue.denoiseModel) {
                        ForEach(DenoiseModel.allCases) { model in
                            Text(model.label).tag(model)
                        }
                    }.disabled(queue.isRunning)
                    Text("The selected model is used for each image in the batch. All four models work offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Output") {
                    Picker("Export format", selection: $queue.exportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }.disabled(queue.isRunning)
                    Text("Files → On My iPhone / iPad → RawDenoise → denoised")
                        .font(.footnote).textSelection(.enabled)
                    Text("\(queue.exportFormat.details) · originals are preserved")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !queue.items.isEmpty {
                    Section("Images") {
                        ForEach(queue.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.name).lineLimit(2)
                                Text(item.status).font(.caption).foregroundStyle(.secondary)
                                if let progress = item.progress { ProgressView(value: progress) }
                                if let output = item.output {
                                    ShareLink(item: output) { Label("Share \(output.pathExtension.uppercased())", systemImage: "square.and.arrow.up") }
                                        .font(.caption)
                                }
                            }.padding(.vertical, 3)
                        }
                    }
                }
                Section {
                    Button(queue.isRunning ? "Denoising…" : "Denoise queued images", systemImage: "sparkles") {
                        queue.start()
                    }.disabled(queue.isRunning || queue.isImporting || !queue.hasPending)
                    if queue.isRunning {
                        Button("Cancel", role: .destructive) { queue.cancel() }
                    } else if !queue.items.isEmpty || queue.failedImportCount > 0 {
                        Button("Clear list", role: .destructive) { queue.clear() }
                            .disabled(queue.isImporting)
                    }
                    if queue.isImporting {
                        ProgressView(queue.importStatus, value: queue.importProgress)
                        Button("Cancel import", role: .destructive) { queue.cancel() }
                    }
                    if !queue.isImporting && queue.failedImportCount > 0 {
                        Button("Retry imports (\(queue.failedImportCount))") { queue.retryImports() }
                            .disabled(queue.isRunning)
                    }
                }
                Section {
                    Text("Uses RawForge TreeNet through Core ML. Keep the app open while processing. RAW support depends on your iOS version and camera.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("RawForge © 2025 rymuelle · MIT License")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("RawDenoise")
            .sheet(isPresented: $selecting) {
                RAWFilePicker(onSelection: { urls in
                    queue.importFiles(urls)
                    selecting = false
                }, onCancel: {
                    selecting = false
                })
            }
            .alert("RawDenoise", isPresented: Binding(get: { queue.message != nil }, set: { if !$0 { queue.message = nil } })) {
                Button("OK") { queue.message = nil }
            } message: { Text(queue.message ?? "") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { queue.cancelProcessing() }
            }
        }
    }
}
