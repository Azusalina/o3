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
                Section("Output") {
                    Text("Files → On My iPhone / iPad → RawDenoise → denoised")
                        .font(.footnote).textSelection(.enabled)
                    Text("16-bit TIFF · original RAW files are preserved")
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
                                    ShareLink(item: output) { Label("Share TIFF", systemImage: "square.and.arrow.up") }
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
                    } else if !queue.items.isEmpty {
                        Button("Clear list", role: .destructive) { queue.clear() }
                            .disabled(queue.isImporting)
                    }
                    if queue.isImporting { ProgressView("Copying selected files…") }
                }
                Section {
                    Text("Uses RawForge TreeNet Super Light through Core ML. Keep the app open while processing. RAW support depends on your iOS version and camera.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("RawForge © 2025 rymuelle · MIT License")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("RawDenoise")
            .fileImporter(isPresented: $selecting, allowedContentTypes: [.rawImage], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): queue.importFiles(urls)
                case .failure(let error): queue.message = error.localizedDescription
                }
            }
            .alert("RawDenoise", isPresented: Binding(get: { queue.message != nil }, set: { if !$0 { queue.message = nil } })) {
                Button("OK") { queue.message = nil }
            } message: { Text(queue.message ?? "") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { queue.cancel() }
            }
        }
    }
}
