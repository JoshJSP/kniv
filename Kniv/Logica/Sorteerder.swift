import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Kiest het bakje voor een notitie. Eén antwoord = zeker, twee = Kniv twijfelt en vraagt het.
/// Volgorde: bakjesnaam letterlijk genoemd → wat Kniv van jou leerde → Apple's taalmodel op het toestel → trefwoorden.
enum Sorteerder {
    static let standaardBakjes = ["School", "Boodschappen", "Ideeën", "To-do", "Persoonlijk"]

    static let trefwoorden: [String: [String]] = [
        "School": ["school", "les", "lessen", "college", "tentamen", "toets", "opdracht", "deadline", "buas", "huiswerk",
                   "project", "presentatie", "leren", "studie", "docent", "rooster", "hoofdstuk", "blok", "inleveren", "assignment"],
        "Boodschappen": ["melk", "brood", "eieren", "kaas", "boter", "boodschappen", "supermarkt", "jumbo", "ah", "albert heijn",
                         "lidl", "aldi", "pasta", "rijst", "groente", "fruit", "appels", "bananen", "vlees", "kip", "wc-papier",
                         "shampoo", "koffie", "thee", "yoghurt", "chips", "drinken", "halen"],
        "To-do": ["bellen", "mailen", "regelen", "moet", "vergeten", "afspraak", "betalen", "opruimen", "maken", "fixen",
                  "sturen", "aanvragen", "opzeggen", "wassen", "was", "todo", "to-do", "straks"],
        "Persoonlijk": ["oma", "opa", "mama", "papa", "moeder", "vader", "zus", "broer", "verjaardag", "vriendin", "vriend",
                        "cadeau", "voel", "dagboek", "gezondheid", "dokter", "tandarts", "sporten"],
        "Ideeën": ["idee", "ideeën", "app", "misschien", "concept", "bedenken", "plan", "zou", "wat als", "inspiratie",
                   "ontwerp", "verhaal", "game"],
    ]

    static let stopwoorden: Set<String> = ["voor", "naar", "maar", "even", "nog", "niet", "met", "van", "een", "het", "de",
                                           "dat", "die", "wat", "als", "ook", "moet", "morgen", "vandaag", "the", "and", "with"]

    static func sorteer(_ tekst: String, bakjes: [String]) async -> [String] {
        let namen = bakjes.isEmpty ? standaardBakjes : bakjes
        let klein = tekst.lowercased()
        if let genoemd = namen.first(where: { klein.contains($0.lowercased()) }) { return [genoemd] }
        if let geleerd = uitGeleerd(klein, namen: namen) { return [geleerd] }
        // Hangt het model, dan niet eeuwig wachten: na 4 seconden de trefwoorden.
        if let model = await Tijdslimiet.binnen(4, { await vraagModel(tekst, namen: namen) }) { return model }
        return opTrefwoorden(tekst, namen: namen)
    }

    static func tokens(_ klein: String) -> Set<String> {
        Set(klein.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted).filter { !$0.isEmpty })
    }

    static func opTrefwoorden(_ tekst: String, namen: [String]) -> [String] {
        let klein = tekst.lowercased()
        let woorden = tokens(klein)
        var scores: [String: Int] = [:]
        for (bakje, lijst) in trefwoorden where namen.contains(bakje) {
            for w in lijst where w.contains(" ") ? klein.contains(w) : woorden.contains(w) {
                scores[bakje, default: 0] += 1
            }
        }
        let top = scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        if let eerste = top.first {
            if top.count > 1, top[1].value == eerste.value { return [eerste.key, top[1].key] }
            return [eerste.key]
        }
        let twijfel = ["Ideeën", "To-do"].filter(namen.contains)
        return twijfel.count == 2 ? twijfel : Array(namen.prefix(2))
    }

    // MARK: leren van jouw keuzes

    static func leer(_ tekst: String, bakje: String) {
        var geleerd = UserDefaults.standard.dictionary(forKey: "geleerd") as? [String: String] ?? [:]
        for t in tokens(tekst.lowercased()) where t.count >= 4 && !stopwoorden.contains(t) {
            geleerd[t] = bakje
        }
        UserDefaults.standard.set(geleerd, forKey: "geleerd")
    }

    static func uitGeleerd(_ klein: String, namen: [String]) -> String? {
        guard let geleerd = UserDefaults.standard.dictionary(forKey: "geleerd") as? [String: String] else { return nil }
        var scores: [String: Int] = [:]
        for t in tokens(klein) { if let b = geleerd[t], namen.contains(b) { scores[b, default: 0] += 1 } }
        let top = scores.sorted { $0.value > $1.value }
        guard let eerste = top.first else { return nil }
        return top.count > 1 && top[1].value == eerste.value ? nil : eerste.key
    }

    // MARK: Apple's taalmodel (iOS 26, iPhone 15 Pro en nieuwer)

    static func vraagModel(_ tekst: String, namen: [String]) async -> [String]? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let sessie = LanguageModelSession(instructions: """
                Je sorteert korte notities in bakjes. Antwoord alleen met de naam van één bakje, precies zoals gegeven. \
                Twijfel je echt tussen twee bakjes, antwoord dan met beide namen gescheiden door |.
                """)
            let vraag = "Bakjes: \(namen.joined(separator: ", "))\nNotitie: \(tekst.prefix(600))"
            guard let antwoord = try? await sessie.respond(to: vraag).content else { return nil }
            let keus = antwoord.split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                .compactMap { k in namen.first { $0.caseInsensitiveCompare(k) == .orderedSame } }
            return keus.isEmpty ? nil : Array(keus.prefix(2))
        }
        #endif
        return nil
    }
}
