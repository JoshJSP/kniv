import Foundation

/// Een kort gesprekje in de doeltaal: Kniv praat terug op jouw niveau en geeft af en toe een tip in het Nederlands.
enum Gesprek {
    struct Beurt: Equatable, Codable {
        enum Rol: String, Codable { case ik, kniv }
        var rol: Rol
        var tekst: String
    }

    struct Antwoord: Equatable {
        var antwoord: String
        var tip: String   // Nederlands, leeg als er niets op te merken viel
    }

    static let maxBeurten = 12
    static let maxTekst = 300

    static func instructies(taalNaam: String, niveau: String, onderwerp: String) -> String {
        "Je bent een vriendelijke gesprekspartner voor een Nederlandstalige die \(taalNaam) leert op ERK-niveau \(niveau). "
            + "Het gesprek gaat over: \(String(onderwerp.prefix(80))). Praat alleen in het \(taalNaam), nooit moeilijker dan niveau \(niveau), "
            + "in 1 of 2 korte zinnen, en stel meestal een vraag terug zodat het gesprek doorgaat. "
            + "Is er nog niets gezegd, begin dan zelf met een korte begroeting en een vraag. "
            + "Zit er in het laatste bericht van de leerling een duidelijke fout, zet dan in \"tip\" in het Nederlands kort hoe het wel moet; anders laat je \"tip\" leeg. "
            + "Antwoord alleen met JSON: {\"antwoord\": \"...\", \"tip\": \"...\"}"
    }

    /// De laatste beurten als tekst voor het model, ingekort.
    static func verloop(_ beurten: [Beurt]) -> String {
        let laatste = beurten.suffix(maxBeurten)
        guard !laatste.isEmpty else { return "(Nog niets gezegd.)" }
        return laatste.map { "\($0.rol == .ik ? "Leerling" : "Jij"): \(String($0.tekst.prefix(maxTekst)))" }.joined(separator: "\n")
    }

    /// Voor de online functie: de beurten als JSON-tekst (ingekort), zodat het in een tekstveld past.
    static func alsJSON(_ beurten: [Beurt]) -> String {
        let kort = beurten.suffix(maxBeurten).map { Beurt(rol: $0.rol, tekst: String($0.tekst.prefix(maxTekst))) }
        return (try? JSONEncoder().encode(Array(kort))).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    static func ontleed(_ data: Data) -> Antwoord? {
        guard let s = String(data: data, encoding: .utf8),
              let begin = s.firstIndex(of: "{"), let eind = s.lastIndex(of: "}"), begin < eind,
              let json = (try? JSONSerialization.jsonObject(with: Data(s[begin...eind].utf8))) as? [String: Any] else { return nil }
        let antwoord = ((json["antwoord"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = ((json["tip"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !antwoord.isEmpty else { return nil }
        return Antwoord(antwoord: antwoord, tip: tip)
    }
}
