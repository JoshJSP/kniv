import Foundation
import NaturalLanguage

/// Oefenen na een leesstukje: vragen over de tekst, zelf schrijven en naspreken.
enum Oefenen {
    /// Meerkeuzevraag over de tekst, in de doeltaal.
    struct Vraag: Equatable, Codable {
        var vraag: String
        var opties: [String]
        var goed: Int
    }

    /// Een eigen zin, nagekeken. `uitleg` is Nederlands.
    struct Verbetering: Equatable {
        var goed: Bool
        var verbeterd: String
        var uitleg: String
    }

    /// Eén woord uit de zin die je naspreekt, en of het verstaan is.
    struct Nagezegd: Equatable {
        var woord: String
        var goed: Bool
    }

    static let maxTekst = 2000
    static let maxZin = 300

    // MARK: vragen

    static func vragenInstructies(taalNaam: String, niveau: String) -> String {
        "Je maakt begripsvragen bij een korte tekst voor een Nederlandstalige die \(taalNaam) leert op ERK-niveau \(niveau). "
            + "Maak 3 meerkeuzevragen over de inhoud, in het \(taalNaam) en niet moeilijker dan niveau \(niveau). "
            + "Elke vraag heeft 3 korte antwoorden waarvan er precies één klopt volgens de tekst. "
            + "Antwoord alleen met JSON: {\"vragen\": [{\"vraag\": \"...\", \"opties\": [\"...\", \"...\", \"...\"], \"goed\": index van het goede antwoord, vanaf 0}]}"
    }

    /// {"vragen":[…]}, ook in ```json … ```. Vragen die niet kloppen vallen weg; maximaal 5.
    static func ontleedVragen(_ data: Data) -> [Vraag] {
        guard let json = object(data), let lijst = json["vragen"] as? [[String: Any]] else { return [] }
        let vragen: [Vraag] = lijst.compactMap { v in
            let vraag = ((v["vraag"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let opties = ((v["opties"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            let goed = (v["goed"] as? Int) ?? (v["goed"] as? String).flatMap { Int($0) } ?? -1
            guard !vraag.isEmpty, (2...4).contains(opties.count), !opties.contains(where: \.isEmpty),
                  Set(opties).count == opties.count, opties.indices.contains(goed) else { return nil }
            return Vraag(vraag: vraag, opties: opties, goed: goed)
        }
        return Array(vragen.prefix(5))
    }

    /// Vragen bewaren bij het stukje (als JSON-tekst), zodat ze bij teruglezen niet opnieuw gemaakt hoeven.
    static func bewaar(_ vragen: [Vraag]) -> String {
        struct Omhulsel: Encodable { let vragen: [Vraag] }
        return (try? JSONEncoder().encode(Omhulsel(vragen: vragen))).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func bewaardeVragen(_ json: String) -> [Vraag] { json.isEmpty ? [] : ontleedVragen(Data(json.utf8)) }

    // MARK: schrijven

    static func verbeterInstructies(taalNaam: String, niveau: String) -> String {
        "Je kijkt een zin na van een Nederlandstalige die \(taalNaam) leert op ERK-niveau \(niveau). "
            + "Verbeter alleen echte fouten (spelling, grammatica, woordkeus) en laat de rest zoals het is. "
            + "Antwoord alleen met JSON: {\"goed\": true als er niets te verbeteren viel, \"verbeterd\": de zin in goed \(taalNaam), "
            + "\"uitleg\": in het Nederlands, maximaal 2 korte zinnen over wat er anders moet en waarom, of een kort compliment als het goed was}"
    }

    static func verbeterVraag(zin: String, onderwerp: String) -> String {
        "Onderwerp: \(String(onderwerp.prefix(200)))\nZin: \(String(zin.prefix(maxZin)))"
    }

    static func ontleedVerbetering(_ data: Data) -> Verbetering? {
        guard let json = object(data) else { return nil }
        let verbeterd = ((json["verbeterd"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let uitleg = ((json["uitleg"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let goed = (json["goed"] as? Bool) ?? ((json["goed"] as? String)?.lowercased() == "true")
        guard !verbeterd.isEmpty || goed else { return nil }
        return Verbetering(goed: goed, verbeterd: verbeterd, uitleg: uitleg)
    }

    // MARK: naspreken

    /// Zinnen om na te zeggen: 3 tot 14 woorden, zoals ze in de tekst staan.
    static func zinnen(uit tekst: String, taal code: String) -> [String] {
        let knipper = NLTokenizer(unit: .sentence)
        knipper.string = tekst
        var uit: [String] = []
        knipper.enumerateTokens(in: tekst.startIndex..<tekst.endIndex) { bereik, _ in
            let zin = String(tekst[bereik]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (3...14).contains(Woorden.knip(zin, taal: code).count) { uit.append(zin) }
            return true
        }
        return uit
    }

    /// Welke woorden van de doelzin zaten in wat de herkenner verstond, in de goede volgorde
    /// (langste gemeenschappelijke reeks). Hoofdletters en leestekens tellen niet, accenten wel.
    static func vergelijk(doel: String, gehoord: String, taal code: String) -> [Nagezegd] {
        let d = Woorden.knip(doel, taal: code).map(\.tekst)
        let g = Woorden.knip(gehoord, taal: code).map { sleutel($0.tekst) }
        let ds = d.map { sleutel($0) }
        guard !d.isEmpty else { return [] }
        // LCS-tabel; zinnen zijn kort, dus O(n·m) is prima
        var t = Array(repeating: Array(repeating: 0, count: g.count + 1), count: ds.count + 1)
        for i in stride(from: ds.count - 1, through: 0, by: -1) {
            for j in stride(from: g.count - 1, through: 0, by: -1) {
                t[i][j] = ds[i] == g[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var goed = Array(repeating: false, count: ds.count)
        var i = 0, j = 0
        while i < ds.count && j < g.count {
            if ds[i] == g[j] { goed[i] = true; i += 1; j += 1 }
            else if t[i + 1][j] >= t[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return zip(d, goed).map { Nagezegd(woord: $0, goed: $1) }
    }

    private static func sleutel(_ woord: String) -> String {
        woord.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Alles tussen de eerste { en de laatste }, als JSON-object.
    private static func object(_ data: Data) -> [String: Any]? {
        guard let s = String(data: data, encoding: .utf8),
              let begin = s.firstIndex(of: "{"), let eind = s.lastIndex(of: "}"), begin < eind else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(s[begin...eind].utf8))) as? [String: Any]
    }
}
