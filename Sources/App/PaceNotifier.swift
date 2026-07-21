import Foundation
import UserNotifications
import UsageCore

/// Posts a local macOS notification when a usage window's pace crosses the Fast
/// boundary (`PaceAlerts` decides *when*; this decides *how it reads*).
///
/// `UNUserNotificationCenter.current()` requires a bundled, code-signed app — it
/// raises in a bare `swift run` executable (no bundle identifier). So every entry
/// point is guarded on `Bundle.main.bundleIdentifier`; unbundled dev runs simply
/// no-op instead of crashing. build.sh ships the proper bundle.
@MainActor
final class PaceNotifier {
    private var authorized = false
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// Ask once for permission. Safe to call repeatedly; the OS remembers the grant.
    func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    /// Human-readable notification for one crossing. `accountName` is nil for a
    /// single account (no need to disambiguate).
    func notify(_ alert: PaceAlert, accountName: String?, window: PaceWindowLabel, percent: Double?) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        let prefix = accountName.map { "\($0) · " } ?? ""
        let pct = Format.percent(percent)
        switch alert {
        case .crossedToFast:
            content.title = "🔥 \(window.short) is burning Fast"
            content.body = "\(prefix)\(window.long) crossed to Fast pace (\(pct) used)."
        case .droppedBelowFast:
            content.title = "\(window.short) eased off Fast"
            content.body = "\(prefix)\(window.long) is back below Fast pace (\(pct) used)."
        }
        content.sound = .default
        // Fire immediately (nil trigger); unique id so alerts never coalesce.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// The two label forms used in a pace notification, per window.
enum PaceWindowLabel {
    case session, weekly, fable

    var short: String {
        switch self {
        case .session: return "5-hour limit"
        case .weekly: return "Weekly limit"
        case .fable: return "Current week (Fable)"
        }
    }
    /// Currently the same as `short`; kept separate so the title (short) and body
    /// (long) can diverge later without touching call sites.
    var long: String { short }
}
