import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

// Small pieces every binder screen shares: the side-effects coordinator in the
// environment, human error alerts, photo thumbnails and phone links.

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
        self.init(
            title: action ?? String(localized: "Nu a mers", comment: "Title of an error alert."),
            message: SaveFailure.message(for: error, formKept: false)
        )
    }
}

/// What to tell a person when saving failed: what happened, in plain words, and
/// what to do. Engine errors already speak plain Romanian; system errors never
/// reach the screen as they are.
enum SaveFailure {
    /// - Parameter formKept: the screen stays open with what the person filled in,
    ///   so the message can say nothing was lost.
    static func message(for error: any Error, formKept: Bool) -> String {
        // The app's own errors are written in plain Romanian; system errors are not.
        if String(reflecting: type(of: error)).hasPrefix("DosarCuSina."), let text = (error as? LocalizedError)?.errorDescription {
            return text
        }
        let kept = formKept ? " " + String(localized: "Ce ai completat e încă aici.", comment: "Reassurance after a failed save: the form keeps what was typed.") : ""
        if isOutOfSpace(error) {
            return String(localized: "Telefonul nu mai are spațiu liber. Eliberează puțin spațiu, apoi încearcă din nou.", comment: "Save failed because the phone is full.") + kept
        }
        return String(localized: "Nu am putut salva. Încearcă din nou; dacă tot nu merge, repornește aplicația.", comment: "Generic error message.") + kept
    }

    /// A full disk, as the file system or the database reports it, at any depth.
    static func isOutOfSpace(_ error: any Error) -> Bool {
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError { return true }
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC) { return true }
            if nsError.domain == "NSSQLiteErrorDomain" && nsError.code == 13 { return true } // SQLITE_FULL
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
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

// MARK: - Call

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
