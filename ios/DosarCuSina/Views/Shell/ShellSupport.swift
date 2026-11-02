import SwiftUI
import SwiftData
import UIKit

// Small pieces every binder screen shares: the side-effects coordinator in the
// environment, human error alerts, photo thumbnails and copy-to-clipboard.

extension EnvironmentValues {
    /// The pipeline that turns saved data into reminders, badge and widgets.
    /// Nil until the store is open.
    @Entry var sideEffects: SideEffectsCoordinator? = nil
}

// MARK: - Errors

/// An error ready to show: what happened and what to do next.
struct UserFacingError: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String

    init(title: String = String(localized: "Nu a mers", comment: "Title of an error alert."), message: String) {
        self.title = title
        self.message = message
    }

    /// Wraps an engine error. Engine errors already speak plain Romanian; anything
    /// else gets a generic sentence that still says what to do.
    init(_ error: any Error, doing action: String? = nil) {
        let text = (error as? LocalizedError)?.errorDescription
        self.init(
            title: action ?? String(localized: "Nu a mers", comment: "Title of an error alert."),
            message: text ?? String(localized: "Nu am putut salva. Încearcă din nou; dacă tot nu merge, repornește aplicația.", comment: "Generic error message.")
        )
    }
}

extension View {
    /// Shows `error` as an alert with one button that closes it.
    func userErrorAlert(_ error: Binding<UserFacingError?>) -> some View {
        alert(
            error.wrappedValue?.title ?? "",
            isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } }),
            presenting: error.wrappedValue
        ) { _ in
            Button(role: .cancel) {} label: { Text("Am înțeles", comment: "Button that closes an error alert.") }
        } message: { error in
            Text(verbatim: error.message)
        }
    }
}

// MARK: - Photos

/// Small decoded copies of asset photos, so a grid of boxes never decodes full-size images.
@MainActor
enum PhotoThumbnails {
    private static let cache = NSCache<NSString, UIImage>()

    /// A thumbnail for `data`, cached by `key` (an asset id plus its last change).
    static func image(for data: Data?, key: String, side: CGFloat = 160) -> Image? {
        guard let data else { return nil }
        let cacheKey = "\(key)-\(Int(side))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return Image(uiImage: cached) }
        guard let image = UIImage(data: data) else { return nil }
        let scale = side * 3 / max(image.size.width, image.size.height, 1)
        let size = scale < 1 ? CGSize(width: image.size.width * scale, height: image.size.height * scale) : image.size
        let thumbnail = image.preparingThumbnail(of: size) ?? image
        cache.setObject(thumbnail, forKey: cacheKey)
        return Image(uiImage: thumbnail)
    }
}

extension Asset {
    /// A thumbnail of the asset's photo, if it has one.
    @MainActor
    func thumbnail(side: CGFloat = 160) -> Image? {
        PhotoThumbnails.image(for: photoData, key: "\(id.uuidString)-\(updatedAt.timeIntervalSince1970)", side: side)
    }
}

// MARK: - Copy and call

@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

enum PhoneLinks {
    /// A `tel:` link for a phone number, keeping only the digits and a leading plus.
    static func call(_ phone: String) -> URL? {
        let normalized = FieldFormatter.normalizePhone(phone)
        guard normalized.count >= 3 else { return nil }
        return URL(string: "tel:\(normalized)")
    }

    /// An `sms:` link for a phone number.
    static func message(_ phone: String) -> URL? {
        let normalized = FieldFormatter.normalizePhone(phone)
        guard normalized.count >= 3 else { return nil }
        return URL(string: "sms:\(normalized)")
    }
}

// MARK: - Templates

extension CategoryTemplate {
    var tintColor: Color { tint.color }
}

extension Asset {
    /// The symbol to draw for this asset: its own, else its category's.
    func symbol(template: CategoryTemplate?) -> String {
        symbolOverride ?? template?.symbol ?? "square.grid.2x2.fill"
    }

    func tintColor(template: CategoryTemplate?) -> Color {
        (tintOverride ?? template?.tint ?? .gray).color
    }
}
