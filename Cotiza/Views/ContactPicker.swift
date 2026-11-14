import Contacts
import ContactsUI
import SwiftUI

/// What Cotiza keeps from a picked contact.
nonisolated struct PickedContact: Equatable, Sendable {
    var name: String
    var phone: String
    var email: String
    var address: String

    init(name: String, phone: String = "", email: String = "", address: String = "") {
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
    }

    init(_ contact: CNContact) {
        let formatted = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        name = formatted.isEmpty ? contact.organizationName : formatted
        // Mobile first: that's the number a text or WhatsApp message reaches.
        let phones = contact.phoneNumbers
        let mobile = phones.first { [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone].contains($0.label) } ?? phones.first
        phone = mobile?.value.stringValue ?? ""
        email = (contact.emailAddresses.first?.value as String?) ?? ""
        address = contact.postalAddresses.first.map {
            CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress).replacingOccurrences(of: "\n", with: ", ")
        } ?? ""
    }

    /// Fills a client's empty fields; never overwrites what the contractor already typed.
    @MainActor
    func fill(_ client: Client) {
        if client.name.trimmingCharacters(in: .whitespaces).isEmpty { client.name = name }
        if client.phone.isEmpty { client.phone = phone }
        if client.email.isEmpty { client.email = email }
        if client.address.isEmpty { client.address = address }
    }
}

extension View {
    /// Shows the system contact picker. It runs outside the app, so no Contacts permission is needed.
    func contactPicker(isPresented: Binding<Bool>, onPick: @escaping (PickedContact) -> Void) -> some View {
        background(ContactPickerPresenter(isPresented: isPresented, onPick: onPick))
    }
}

/// `CNContactPickerViewController` misbehaves when embedded in a SwiftUI sheet, so it is presented from UIKit.
private struct ContactPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (PickedContact) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        DispatchQueue.main.async { host.present(picker, animated: true) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPickerPresenter
        init(parent: ContactPickerPresenter) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onPick(PickedContact(contact))
            parent.isPresented = false
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}
