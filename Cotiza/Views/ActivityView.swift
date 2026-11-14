import SwiftUI
import UIKit

/// The system share sheet. Used for WhatsApp (WhatsApp takes the PDF and the note; the contractor picks
/// the chat there) and for sharing signing links.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: (_ completed: Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
