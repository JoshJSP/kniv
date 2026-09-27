import AppIntents

/// Siri kiest voor je, zonder de app te openen.
struct DobbelIntent: AppIntent {
    static var title: LocalizedStringResource = "Gooi een dobbelsteen"
    static var openAppWhenRun = false
    @Parameter(title: "Aantal stenen", default: 1, inclusiveRange: (1, 6)) var aantal: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let worp = (0..<aantal).map { _ in Int.random(in: 1...6) }
        let tekst = worp.count == 1 ? String(localized: "Je gooide \(worp[0]).")
            : String(localized: "Je gooide \(worp.map(String.init).joined(separator: ", ")). Samen \(worp.reduce(0, +)).")
        return .result(dialog: IntentDialog(stringLiteral: tekst))
    }
}

struct MuntIntent: AppIntent {
    static var title: LocalizedStringResource = "Kop of munt"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: Bool.random() ? String(localized: "Kop!") : String(localized: "Munt!")))
    }
}

struct KiesVoorMijIntent: AppIntent {
    static var title: LocalizedStringResource = "Kies iets"
    static var description = IntentDescription("Draait het rad met de opties die je in Kniv hebt staan.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let opties = (UserDefaults.standard.string(forKey: "kiesOpties") ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard let keus = opties.randomElement() else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Zet eerst een paar opties in het rad van Kniv.")))
        }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Het wordt: \(keus)!")))
    }
}
