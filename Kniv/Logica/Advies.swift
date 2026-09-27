import Foundation

enum Weer {
    struct Uur {
        let uur: Int
        let kans: Int        // neerslagkans %
        let mm: Double
        let temp: Double
    }

    /// Eén zin die ertoe doet, of niets: regen op komst, of koud genoeg voor een jas.
    static func advies(_ uren: [Uur]) -> String? {
        if let regen = uren.first(where: { $0.kans >= 50 && $0.mm >= 0.2 }) {
            return String(format: String(localized: "Regen rond %02d:00, paraplu mee"), regen.uur)
        }
        if let koudst = uren.map(\.temp).min(), koudst < 8 {
            return String(format: String(localized: "Fris vandaag (%d°), jas aan"), Int(koudst.rounded()))
        }
        return nil
    }
}

enum Verjaardag {
    /// "verjaardag Sam 12 mei", "Lisa jarig 3-4" → dag en maand, voor een jaarlijkse herinnering.
    static func vind(in tekst: String) -> (dag: Int, maand: Int)? {
        let klein = tekst.lowercased()
        guard ["verjaardag", "jarig", "birthday", "bday"].contains(where: klein.contains) else { return nil }
        if let m = Herinnering.eersteMatch(#"\b(\d{1,2})\s*(jan|feb|mrt|maa|mar|apr|mei|may|jun|jul|aug|sep|okt|oct|nov|dec)"#, in: klein),
           let d = Int(m[1]), let maand = Herinnering.maanden[m[2]], (1...31).contains(d) {
            return (d, maand)
        }
        if let m = Herinnering.eersteMatch(#"\b(\d{1,2})[-/](\d{1,2})\b"#, in: klein),
           let d = Int(m[1]), let maand = Int(m[2]), (1...31).contains(d), (1...12).contains(maand) {
            return (d, maand)
        }
        return nil
    }
}

enum Studieplan {
    /// "120 pagina's" → (120, "pagina's"). Het getal mag overal staan.
    static func werk(uit tekst: String) -> (aantal: Int, eenheid: String)? {
        guard let m = Herinnering.eersteMatch(#"(\d{1,5})\s*(.*)"#, in: tekst.trimmingCharacters(in: .whitespaces)),
              let n = Int(m[1]), n > 0 else { return nil }
        return (n, m[2].trimmingCharacters(in: .whitespaces))
    }

    /// Hoeveel per dag, inclusief vandaag, om op tijd klaar te zijn.
    static func perDag(werk: Int, dagen: Int) -> Int {
        max(1, Int((Double(werk) / Double(max(dagen, 1))).rounded(.up)))
    }
}
