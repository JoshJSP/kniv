import UserNotifications

/// Knoppen in meldingen: bij een timer "+5 min", bij een herinnering "Over een uur" of "Morgen". Werkt zonder Kniv te openen.
final class MeldingActies: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MeldingActies()

    static let timer = "kniv.timer"
    static let herinnering = "kniv.herinnering"
    static let herhaal = "kniv.herhaal"

    func registreer() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        let plus5 = UNNotificationAction(identifier: "plus5", title: String(localized: "+5 min"), options: [])
        let uur = UNNotificationAction(identifier: "uur", title: String(localized: "Over een uur"), options: [])
        let morgen = UNNotificationAction(identifier: "morgen", title: String(localized: "Morgen"), options: [])
        let stop = UNNotificationAction(identifier: "stop", title: String(localized: "Niet meer herinneren"), options: [.destructive])
        c.setNotificationCategories([
            UNNotificationCategory(identifier: Self.herhaal, actions: [stop], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.timer, actions: [plus5], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.herinnering, actions: [uur, morgen], intentIdentifiers: []),
        ])
    }

    /// Ook meldingen tonen als Kniv open is (bijvoorbeeld een timer terwijl je in een ander mesje zit).
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive antwoord: UNNotificationResponse) async {
        let oud = antwoord.notification.request.content
        if antwoord.actionIdentifier == "stop" {
            // "herinnering.<uid>.r" of "herinnering.<uid>.3": alles met dezelfde uid eruit.
            let basis = antwoord.notification.request.identifier.split(separator: ".").prefix(2).joined(separator: ".")
            let wachtend = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(basis) }
            c.removePendingNotificationRequests(withIdentifiers: wachtend)
            return
        }
        let seconden: TimeInterval
        switch antwoord.actionIdentifier {
        case "plus5": seconden = 5 * 60
        case "uur": seconden = 3600
        case "morgen":
            let morgen9 = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86_400))!
            seconden = morgen9.timeIntervalSinceNow
        default: return
        }
        let nieuw = UNMutableNotificationContent()
        nieuw.title = oud.title
        nieuw.body = oud.body
        nieuw.sound = .default
        nieuw.categoryIdentifier = oud.categoryIdentifier
        try? await c.add(UNNotificationRequest(identifier: UUID().uuidString, content: nieuw,
                                               trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(seconden, 1), repeats: false)))
    }
}
