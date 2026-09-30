import Foundation

/// Wat het toestel zelf kan voor een taal; de rest gaat online (via de functie `taal`).
struct TaalVermogen: Equatable {
    var tekstOpToestel: Bool
    var vertalenOpToestel: Bool
    var stem: Bool

    enum Bron: Equatable { case toestel, online }
    enum WoordBron: Equatable { case woordenlijst, toestel, online }

    var tekstBron: Bron { tekstOpToestel ? .toestel : .online }

    /// Betekenis van een woord: eerst de woordenlijst van het stukje, dan vertalen op het toestel, anders online.
    func woordBron(inWoordenlijst: Bool) -> WoordBron {
        if inWoordenlijst { return .woordenlijst }
        return vertalenOpToestel ? .toestel : .online
    }

    static let niets = TaalVermogen(tekstOpToestel: false, vertalenOpToestel: false, stem: false)
}

/// Alle talen die het toestel kent, met hun naam in de taal van Kniv.
enum Talen {
    /// Twee-letter ISO-codes zonder Nederlands, naam met hoofdletter, gesorteerd op naam.
    static func alle(in taal: Locale = .current) -> [(code: String, naam: String)] {
        var gezien = Set<String>()
        let lijst: [(code: String, naam: String)] = Locale.LanguageCode.isoLanguageCodes
            .map { $0.identifier }
            .filter { $0.count == 2 && $0 != "nl" }
            .compactMap { (code: String) -> (code: String, naam: String)? in
                guard let naam = taal.localizedString(forLanguageCode: code), naam.lowercased() != code else { return nil }
                return (code: code, naam: hoofdletter(naam))
            }
        return lijst
            .sorted { $0.naam.compare($1.naam, locale: taal) == .orderedAscending }
            .filter { gezien.insert($0.naam).inserted }   // oude dubbele codes (iw/he) maar één keer
    }

    static func naam(_ code: String, in taal: Locale = .current) -> String {
        taal.localizedString(forLanguageCode: code).map(hoofdletter) ?? code.uppercased()
    }

    /// Exacte code eerst, daarna talen waarvan de naam de zoektekst bevat.
    static func zoek(_ tekst: String, in lijst: [(code: String, naam: String)]) -> [(code: String, naam: String)] {
        let t = tekst.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return lijst }
        let exact = lijst.filter { $0.code == t }
        let bevat = lijst.filter { $0.code != t && $0.naam.range(of: t, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return exact + bevat
    }

    private static func hoofdletter(_ naam: String) -> String { naam.prefix(1).uppercased() + naam.dropFirst() }
}
