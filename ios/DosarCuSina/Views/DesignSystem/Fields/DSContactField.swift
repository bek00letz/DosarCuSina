import SwiftUI
import Contacts
import ContactsUI

/// A person linked to an asset: mechanic, vet, family doctor, tenant.
/// A plain value so it can be stored by the field system without importing Contacts.
struct DSContactValue: Hashable, Sendable, Codable {
    var name: String
    var phone: String?
    var email: String?
    /// The Contacts identifier, if the person was picked from Contacts. Only useful on this device.
    var contactIdentifier: String?
}

/// Picks someone from Contacts. The system picker runs out of process,
/// so the app needs no Contacts permission and only sees the person chosen.
struct DSContactField: View {
    let title: LocalizedStringKey
    @Binding var contact: DSContactValue?
    var footnote: LocalizedStringKey?

    @State private var isPicking = false

    init(_ title: LocalizedStringKey, contact: Binding<DSContactValue?>, footnote: LocalizedStringKey? = nil) {
        self.title = title
        self._contact = contact
        self.footnote = footnote
    }

    var body: some View {
        DSFieldContainer(
            title: Text(title),
            isFocused: isPicking,
            validation: .valid,
            footnote: footnote.map { Text($0) }
        ) {
            HStack(spacing: DS.Space.s) {
                if let contact {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: contact.name)
                            .foregroundStyle(DS.Palette.label)
                        if let detail = contact.phone ?? contact.email {
                            Text(verbatim: detail)
                                .dsFont(.subheadline, numeric: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: DS.Space.xs)
                    Menu {
                        Button {
                            isPicking = true
                        } label: {
                            Label { Text("Alege alt contact", comment: "Menu item that replaces the linked contact.") } icon: { Image(systemName: "person.crop.circle") }
                        }
                        Button(role: .destructive) {
                            self.contact = nil
                        } label: {
                            Label { Text("Elimină contactul", comment: "Menu item that unlinks the contact from this field.") } icon: { Image(systemName: "person.crop.circle.badge.minus") }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(Text("Opțiuni contact", comment: "VoiceOver label of the menu next to a linked contact."))
                } else {
                    Button {
                        isPicking = true
                    } label: {
                        Label {
                            Text("Alege din Contacte", comment: "Button in an empty contact field.")
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(Text(title))
                }
            }
        }
        .background {
            DSContactPickerPresenter(isPresented: $isPicking) { picked in
                contact = picked
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: contact)
    }
}

/// Presents `CNContactPickerViewController` modally from a hidden host, which is the
/// reliable way to show it from SwiftUI.
private struct DSContactPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onSelect: @MainActor (DSContactValue) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
        Task { @MainActor in
            host.present(picker, animated: true)
        }
    }

    /// The picker calls its delegate on the main thread, so the conformance is main-actor isolated.
    @MainActor
    final class Coordinator: NSObject, @MainActor CNContactPickerDelegate {
        var parent: DSContactPickerPresenter

        init(parent: DSContactPickerPresenter) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            parent.onSelect(DSContactValue(
                name: name.isEmpty ? (contact.organizationName) : name,
                phone: contact.phoneNumbers.first?.value.stringValue,
                email: contact.emailAddresses.first.map { String($0.value) },
                contactIdentifier: contact.identifier
            ))
            parent.isPresented = false
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}
