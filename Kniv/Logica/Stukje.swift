import Foundation
import NaturalLanguage

/// Een leesstukje van het taalmodel: titel, tekst en (bij online stukjes) een woordenlijst.
struct Stukje: Equatable {
    var titel: String
    var tekst: String
    var woorden: [String: String] = [:]   // woord in kleine letters → Nederlandse betekenis

    static let maxOnderwerp = 80

    /// Eigen onderwerp op één regel: witruimte wordt één spatie, maximaal 80 tekens.
    static func schoon(onderwerp: String) -> String {
        String(onderwerp.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(maxOnderwerp))
    }

    /// Instructies voor het taalmodel op de iPhone (Denker).
    static func instructies(taalNaam: String, niveau: String) -> String {
        "Je schrijft korte leesstukjes voor een Nederlandstalige die \(taalNaam) leert. "
            + "Schrijf het stukje alleen in het \(taalNaam), 80 tot 150 woorden, in gewone spreektaal. "
            + "Gebruik niets boven ERK-niveau \(niveau): alleen woorden en zinnen die iemand op dat niveau begrijpt. "
            + "Zet op de eerste regel een korte titel, dan een lege regel, dan de tekst. "
            + "Geen uitleg, geen vertaling, geen opmaak."
    }

    static func prompt(onderwerp: String) -> String { "Onderwerp: " + schoon(onderwerp: onderwerp) }

    /// Antwoord van het toestelmodel: eerste regel is de titel (zonder # * "), de rest de tekst.
    static func ontleed(_ ruw: String) -> Stukje? {
        var regels = ruw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        let rand = CharacterSet(charactersIn: "#*\"\u{201C}\u{201D}\u{201E}").union(.whitespaces)
        let titel = regels.removeFirst().trimmingCharacters(in: rand)
        let tekst = regels.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titel.isEmpty, !tekst.isEmpty else { return nil }
        return Stukje(titel: titel, tekst: tekst)
    }

    /// Antwoord van de functie `taal`: {"titel","tekst","woorden"?}, ook als het in ```json … ``` staat.
    static func ontleedJSON(_ data: Data) -> Stukje? {
        guard let s = String(data: data, encoding: .utf8),
              let begin = s.firstIndex(of: "{"), let eind = s.lastIndex(of: "}"), begin < eind,
              let ruw = try? JSONDecoder().decode(Ruw.self, from: Data(s[begin...eind].utf8)) else { return nil }
        let titel = ruw.titel.trimmingCharacters(in: .whitespacesAndNewlines)
        let tekst = ruw.tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titel.isEmpty, !tekst.isEmpty else { return nil }
        let woorden = Dictionary(ruw.woorden.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { eerste, _ in eerste })
        return Stukje(titel: titel, tekst: tekst, woorden: woorden)
    }

    /// Onwaar als het stukje met meer dan 80% zekerheid Nederlands of Engels is (en dat niet de doeltaal is).
    /// Afrikaans, Fries en Limburgs lijken voor de herkenner op Nederlands; daar geen Nederlands-check.
    func isIn(_ code: String) -> Bool {
        let herkenner = NLLanguageRecognizer()
        herkenner.processString(titel + "\n" + tekst)
        for (taal, kans) in herkenner.languageHypotheses(withMaximum: 3)
        where kans > 0.8 && (taal == .english || (taal == .dutch && !["af", "fy", "li"].contains(code))) && taal.rawValue != code {
            return false
        }
        return true
    }

    /// Velden los gelezen: een kapotte woordenlijst mag het stukje niet kosten.
    private struct Ruw: Decodable {
        var titel = "", tekst = "", woorden: [String: String] = [:]
        enum CodingKeys: String, CodingKey { case titel, tekst, woorden }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            titel = (try? c.decode(String.self, forKey: .titel)) ?? ""
            tekst = (try? c.decode(String.self, forKey: .tekst)) ?? ""
            woorden = (try? c.decode([String: String].self, forKey: .woorden)) ?? [:]
        }
    }
}
