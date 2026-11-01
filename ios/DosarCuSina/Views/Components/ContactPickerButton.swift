import SwiftUI
#if canImport(UIKit)
import UIKit
import ContactsUI
#endif

// MARK: - Contact Data Transfer Object

/// Encapsulates extracted contact data from iOS Contacts address book.
public struct ContactData: Sendable, Equatable {
    public let name: String
    public let phone: String?
    public let email: String?
    public let organization: String?
    
    public init(
        name: String,
        phone: String? = nil,
        email: String? = nil,
        organization: String? = nil
    ) {
        self.name = name
        self.phone = phone
        self.email = email
        self.organization = organization
    }
}

// MARK: - Romanian Phone Formatting & URL Helpers

public enum ContactFormatting {
    
    /// Normalizes raw phone inputs to standard Romanian formatted representation (`+40 7XX XXX XXX`).
    ///
    /// Handles:
    /// - Standard 10-digit mobile (`0722123456`) -> `+40 722 123 456`
    /// - International prefixed (`+40722123456`) -> `+40 722 123 456`
    /// - Double zero prefixed (`0040722123456`) -> `+40 722 123 456`
    /// - Raw country code (`40722123456`) -> `+40 722 123 456`
    public static func formatRomanianPhoneNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        
        var digits = trimmed.filter { $0.isNumber }
        
        if digits.hasPrefix("0040") {
            digits = String(digits.dropFirst(4))
        } else if digits.hasPrefix("40") && digits.count > 10 {
            digits = String(digits.dropFirst(2))
        } else if digits.hasPrefix("0") && digits.count == 10 {
            digits = String(digits.dropFirst(1))
        }
        
        // Romanian mobile numbers (9 digits starting with 7)
        if digits.count == 9 && digits.hasPrefix("7") {
            let part1 = digits.prefix(3)
            let remaining = digits.dropFirst(3)
            let part2 = remaining.prefix(3)
            let part3 = remaining.dropFirst(3)
            return "+40 \(part1) \(part2) \(part3)"
        }
        
        if trimmed.hasPrefix("+") {
            return trimmed
        }
        
        return trimmed
    }
    
    /// Extracts a dialable E.164 string (`+40722123456`).
    public static func dialablePhoneNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isNumber }
        
        if digits.hasPrefix("0040") {
            return "+" + String(digits.dropFirst(2))
        } else if digits.hasPrefix("40") && digits.count > 10 {
            return "+" + digits
        } else if digits.hasPrefix("07") && digits.count == 10 {
            return "+40" + String(digits.dropFirst(1))
        } else if trimmed.hasPrefix("+") {
            return "+" + digits
        }
        
        return digits
    }
    
    /// Generates a `tel://` URL for cellular dialing.
    public static func phoneURL(for rawPhone: String) -> URL? {
        let dialable = dialablePhoneNumber(rawPhone)
        guard !dialable.isEmpty else { return nil }
        return URL(string: "tel://\(dialable)")
    }
    
    /// Generates a direct WhatsApp link (`https://wa.me/<digits>`).
    public static func whatsAppURL(for rawPhone: String) -> URL? {
        var dialable = dialablePhoneNumber(rawPhone)
        if dialable.hasPrefix("+") {
            dialable = String(dialable.dropFirst(1))
        }
        guard !dialable.isEmpty else { return nil }
        return URL(string: "https://wa.me/\(dialable)")
    }
    
    /// Generates a `mailto:` URL.
    public static func emailURL(for rawEmail: String) -> URL? {
        let trimmed = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("@") else { return nil }
        return URL(string: "mailto:\(trimmed)")
    }
}

// MARK: - UIViewControllerRepresentable Picker

#if canImport(UIKit)
public struct ContactPickerViewControllerRepresentable: UIViewControllerRepresentable {
    public var onSelectContact: (ContactData) -> Void
    public var onCancel: (() -> Void)?
    
    public init(
        onSelectContact: @escaping (ContactData) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onSelectContact = onSelectContact
        self.onCancel = onCancel
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    public func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    
    public final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerViewControllerRepresentable
        
        init(parent: ContactPickerViewControllerRepresentable) {
            self.parent = parent
        }
        
        public func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let given = contact.givenName.trimmingCharacters(in: .whitespaces)
            let family = contact.familyName.trimmingCharacters(in: .whitespaces)
            let fullName: String
            if !given.isEmpty || !family.isEmpty {
                fullName = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            } else if !contact.organizationName.isEmpty {
                fullName = contact.organizationName
            } else {
                fullName = "Contact fără nume"
            }
            
            let phone = contact.phoneNumbers.first?.value.stringValue
            let email = contact.emailAddresses.first?.value as String?
            let organization = contact.organizationName.isEmpty ? nil : contact.organizationName
            
            let data = ContactData(
                name: fullName,
                phone: phone,
                email: email,
                organization: organization
            )
            parent.onSelectContact(data)
        }
        
        public func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.onCancel?()
        }
    }
}
#endif

// MARK: - ContactPickerButton

/// High-craft SwiftUI button launching the system address book to pick an associated specialist.
public struct ContactPickerButton: View {
    public let title: String
    public let iconName: String
    public let onSelect: (ContactData) -> Void
    
    @State private var isShowingPicker = false
    
    public init(
        title: String = "Alege din Contacte",
        iconName: String = "person.crop.circle.badge.plus",
        onSelect: @escaping (ContactData) -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: {
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
            isShowingPicker = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        #if canImport(UIKit)
        .sheet(isPresented: $isShowingPicker) {
            ContactPickerViewControllerRepresentable(
                onSelectContact: { data in
                    isShowingPicker = false
                    onSelect(data)
                },
                onCancel: {
                    isShowingPicker = false
                }
            )
            .ignoresSafeArea()
        }
        #endif
    }
}

// MARK: - Contact Action Bar

/// Tactile, Apple-style contact card with 1-tap Call, WhatsApp, and Email action triggers.
public struct ContactActionBar: View {
    public let contactName: String?
    public let contactPhone: String?
    public let contactEmail: String?
    public let contactRole: String?
    public var onEdit: (() -> Void)?
    
    public init(
        contactName: String?,
        contactPhone: String?,
        contactEmail: String?,
        contactRole: String? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.contactName = contactName
        self.contactPhone = contactPhone
        self.contactEmail = contactEmail
        self.contactRole = contactRole
        self.onEdit = onEdit
    }
    
    private var initials: String {
        guard let name = contactName, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2, let first = components.first?.first, let last = components.last?.first {
            return "\(first)\(last)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "?"
    }
    
    public var body: some View {
        if let name = contactName, !name.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    // Concentric avatar badge
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.blue.opacity(0.85), Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 44, height: 44)
                        
                        Text(initials)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if let role = contactRole, !role.isEmpty {
                            Text(role)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.secondary)
                        } else if let phone = contactPhone, !phone.isEmpty {
                            Text(ContactFormatting.formatRomanianPhoneNumber(phone))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if let onEdit = onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Tactile action row
                HStack(spacing: 8) {
                    if let phone = contactPhone, let callURL = ContactFormatting.phoneURL(for: phone) {
                        Link(destination: callURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Sună")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color.green.opacity(0.12))
                            .foregroundColor(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    
                    if let phone = contactPhone, let waURL = ContactFormatting.whatsAppURL(for: phone) {
                        Link(destination: waURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("WhatsApp")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color.mint.opacity(0.12))
                            .foregroundColor(.mint)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    
                    if let email = contactEmail, let mailURL = ContactFormatting.emailURL(for: email) {
                        Link(destination: mailURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Email")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(14)
            #if canImport(UIKit)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            #else
            .background(Color.gray.opacity(0.1))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
    }
}
