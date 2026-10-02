import AppIntents
import SwiftData

/// "Wat staat er vandaag in Kniv?": Siri vertelt je dag in één adem.
struct WatStaatErVandaagIntent: AppIntent {
    static var title: LocalizedStringResource = "Wat staat er vandaag?"
    static var description = IntentDescription("Vertelt je herinneringen van vandaag, open boodschappen, lopende timers en of je een paraplu nodig hebt.")
    static var openAppWhenRun = false

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KnivOpslag.container.mainContext
        let notities = ((try? ctx.fetch(FetchDescriptor<Notitie>())) ?? []).filter { $0.weggegooid == nil && !$0.isVerzegeld }
        let kal = Calendar.current
        var zinnen: [String] = []

        let vandaag = notities.filter { !$0.isVerzegeld }.compactMap { n -> String? in
            guard let m = Herinnering.vind(in: n.zoekTekst, nu: n.gemaakt), kal.isDateInToday(m.dag) else { return nil }
            return m.heeftTijd ? "\(m.dag.formatted(date: .omitted, time: .shortened)) \(n.titel)" : n.titel
        }
        if !vandaag.isEmpty { zinnen.append(String(localized: "Vandaag: \(vandaag.prefix(4).joined(separator: ", ")).")) }

        let boodschappen = Gangpad.volgorde(notities.filter { $0.bakjeNaam == "Boodschappen" }.flatMap { $0.isLijst ? $0.gesorteerdeItems.map(\.tekst) : [$0.titel] }) { $0 }
        if !boodschappen.isEmpty {
            zinnen.append(String(localized: "\(boodschappen.count) boodschappen open, zoals \(boodschappen.prefix(3).joined(separator: ", ")).")) }

        if Pomodoro.shared.loopt { zinnen.append(String(localized: "Je focus loopt nog \(Int(Pomodoro.shared.resterend(Date()) / 60)) minuten.")) }
        let timers = ((try? ctx.fetch(FetchDescriptor<KnivTimer>())) ?? []).filter(\.loopt)
        for t in timers.prefix(2) { zinnen.append(String(localized: "\(t.naam): nog \(Int(t.resterend(Date()) / 60)) minuten.")) }

        await WeerDienst.ververs()
        if let weer = WeerDienst.advies { zinnen.append(weer + ".") }

        return .result(dialog: IntentDialog(stringLiteral: zinnen.isEmpty ? String(localized: "Niks bijzonders vandaag. Geniet ervan!") : zinnen.joined(separator: " ")))
    }
}
