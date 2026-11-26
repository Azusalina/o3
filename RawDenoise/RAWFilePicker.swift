import SwiftUI
import UniformTypeIdentifiers

/// Let Files materialize provider documents and hand us local copies. Do not
/// coordinate a second provider read while its picker is still dismissing.
struct RAWFilePicker: UIViewControllerRepresentable {
    let onSelection: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        makePicker(delegate: context.coordinator)
    }

    func makePicker(delegate: UIDocumentPickerDelegate) -> UIDocumentPickerViewController {
        // Some camera/provider combinations label CR3/NEF/ARW as generic data
        // rather than public.camera-raw-image. Validate the extension on import.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = delegate
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: RAWFilePicker
        private var finished = false
        init(parent: RAWFilePicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !finished else { return }
            finished = true
            parent.onSelection(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !finished else { return }
            finished = true
            parent.onCancel()
        }
    }
}
