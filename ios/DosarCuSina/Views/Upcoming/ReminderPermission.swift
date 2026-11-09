import SwiftUI
import UIKit

/// Notification permission, asked in context: the first time the person saves
/// something that reminds, the app explains in one sentence, then the system
/// asks (through `SideEffectsCoordinator`, right after the save). This gate
/// and Settings are the only places that ask; plain saves never do. If it was
/// refused, screens show calmly how to turn it on; nothing else depends on it.
@MainActor
@Observable
final class ReminderPermission {
    static let shared = ReminderPermission()

    private(set) var status: ReminderAuthorization = .notDetermined
    @ObservationIgnored private let client: any NotificationCenterClient
    @ObservationIgnored private var activation: Task<Void, Never>?

    /// Reads the permission again each time the app becomes active: after the system's
    /// question closes, and after the person comes back from the phone's Settings.
    init(client: any NotificationCenterClient = SystemNotificationCenterClient(),
         becomesActive: Notification.Name = UIApplication.didBecomeActiveNotification) {
        self.client = client
        activation = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: becomesActive).map({ _ in () }) {
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        status = await client.authorization()
    }

    /// Whether a save that reminds should be preceded by the short explanation.
    var needsExplanation: Bool { status == .notDetermined }
}

extension View {
    /// Runs `save` straight away when permission was already decided; otherwise
    /// first shows a short explanation, then saves (and the system asks).
    /// Set `request` to the save to run.
    func reminderPermissionGate(_ request: Binding<ReminderSaveRequest?>) -> some View {
        modifier(ReminderPermissionGate(request: request))
    }
}

/// A save waiting for the permission explanation.
struct ReminderSaveRequest: Identifiable {
    let id = UUID()
    let save: @MainActor () -> Void
}

private struct ReminderPermissionGate: ViewModifier {
    @Binding var request: ReminderSaveRequest?
    @Environment(\.sideEffects) private var sideEffects
    @State private var pending: ReminderSaveRequest?

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id) { _, _ in
                guard let request else { return }
                self.request = nil
                Task {
                    let permission = ReminderPermission.shared
                    await permission.refresh()
                    if permission.needsExplanation {
                        pending = request
                    } else {
                        request.save()
                    }
                }
            }
            .sheet(item: $pending) { request in
                ReminderPermissionExplainer {
                    pending = nil
                    request.save()
                    Task {
                        // The system asks during this pass, which returns with the answer.
                        await sideEffects?.askForPermission()
                        await ReminderPermission.shared.refresh()
                    }
                }
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled()
            }
    }
}

/// The one sentence before the system asks about notifications.
private struct ReminderPermissionExplainer: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Palette.accent)
                    .accessibilityHidden(true)
                Text("Te anunț pe telefon")
                    .dsFont(.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Ca să-ți amintesc la timp, iPhone-ul te întreabă acum o singură dată dacă am voie să-ți trimit notificări. Alege „Permite”.")
                    .dsFont(.body)
                Text("Poți schimba oricând din Setări.")
                    .dsFont(.footnote)
            }
            .padding(DS.Space.xl)
        }
        .dsPinnedAction { DSPrimaryButton("Continuă", action: onContinue) }
    }
}

/// Shown where reminders are set up when notifications are off.
struct ReminderPermissionNotice: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        if ReminderPermission.shared.status == .denied {
            DSNotice(
                .warning,
                title: "Notificările sunt oprite",
                message: "Ca să te anunț, pornește-le din Setări › Dosar cu Șină › Notificări. Termenele rămân oricum aici, în Urmează.",
                actionTitle: "Deschide Setările"
            ) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
        }
    }
}
