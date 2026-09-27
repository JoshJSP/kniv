import Foundation

/// Vindt een moment in een notitie: "morgen oma bellen", "maandag om 14:30", "deadline 9 okt".
enum Herinnering {
    enum Herhaling: Equatable { case dagelijks, wekelijks, elke(dagen: Int) }

    struct Voorstel {
        let dag: Date
        let heeftTijd: Bool
        var herhaal: Herhaling? = nil
    }

    static let dagen = ["zondag": 1, "maandag": 2, "dinsdag": 3, "woensdag": 4, "donderdag": 5, "vrijdag": 6, "zaterdag": 7,
                        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
    static let maanden = ["jan": 1, "feb": 2, "mrt": 3, "maa": 3, "mar": 3, "apr": 4, "mei": 5, "may": 5, "jun": 6,
                          "jul": 7, "aug": 8, "sep": 9, "okt": 10, "oct": 10, "nov": 11, "dec": 12]

    static func vind(in tekst: String, nu: Date = Date()) -> Voorstel? {
        guard var v = eenmalig(in: tekst, nu: nu) ?? herhaling(in: tekst).map({ _ in Voorstel(dag: Calendar.current.startOfDay(for: nu), heeftTijd: false) })
        else { return nil }
        v.herhaal = herhaling(in: tekst)
        return v
    }

    /// "elke dag", "iedere maandag", "elke 3 dagen", "elke 2 weken", "wekelijks".
    static func herhaling(in tekst: String) -> Herhaling? {
        let klein = tekst.lowercased()
        let woorden = Set(klein.components(separatedBy: CharacterSet.letters.inverted))
        if let m = eersteMatch(#"\b(?:elke|iedere|every)\s+(\d+)\s+(dagen|days|weken|weeks)\b"#, in: klein), let n = Int(m[1]), n > 0 {
            return .elke(dagen: m[2].hasPrefix("w") ? n * 7 : n)
        }
        if !woorden.isDisjoint(with: ["dagelijks", "daily"])
            || eersteMatch(#"\b(?:elke|iedere|every)\s+(?:dag|day|ochtend|middag|avond|morning|evening|night)\b"#, in: klein) != nil { return .dagelijks }
        if !woorden.isDisjoint(with: ["wekelijks", "weekly"])
            || eersteMatch(#"\b(?:elke|iedere|every)\s+(week|\w+)\b"#, in: klein).map({ $0[1] == "week" || dagen[$0[1]] != nil }) == true { return .wekelijks }
        return nil
    }

    static func eenmalig(in tekst: String, nu: Date) -> Voorstel? {
        let kal = Calendar.current
        let klein = tekst.lowercased()
        let woorden = Set(klein.components(separatedBy: CharacterSet.letters.inverted))
        let vandaag = kal.startOfDay(for: nu)

        var dag: Date?
        if woorden.contains("overmorgen") {
            dag = kal.date(byAdding: .day, value: 2, to: vandaag)
        } else if woorden.contains("morgen") || woorden.contains("tomorrow") {
            dag = kal.date(byAdding: .day, value: 1, to: vandaag)
        } else if !woorden.isDisjoint(with: ["vandaag", "vanavond", "today", "tonight"]) {
            dag = vandaag
        } else if let wd = dagen.first(where: { woorden.contains($0.key) })?.value {
            dag = kal.nextDate(after: vandaag, matching: DateComponents(weekday: wd), matchingPolicy: .nextTime)
        } else if let m = eersteMatch(#"\b(\d{1,2})\s*(jan|feb|mrt|maa|mar|apr|mei|may|jun|jul|aug|sep|okt|oct|nov|dec)"#, in: klein),
                  let d = Int(m[1]), let maand = maanden[m[2]] {
            var c = kal.dateComponents([.year], from: nu)
            c.month = maand
            c.day = d
            if let kandidaat = kal.date(from: c) {
                dag = kandidaat < vandaag ? kal.date(byAdding: .year, value: 1, to: kandidaat) : kandidaat
            }
        }

        var tijd: (uur: Int, minuut: Int)?
        // "14:30", of "om 14.30"; een los "2.50" is een prijs, geen tijd.
        let ochtend = !woorden.isDisjoint(with: ["ochtend", "morgens", "vroeg", "am"])
        func middag(_ u: Int) -> Int { (1...7).contains(u) && !ochtend ? u + 12 : u }
        if let m = eersteMatch(#"\b(\d{1,2}):(\d{2})\b"#, in: klein) ?? eersteMatch(#"\bom (\d{1,2})\.(\d{2})\b"#, in: klein),
           let u = Int(m[1]), let mi = Int(m[2]), u < 24, mi < 60 {
            tijd = (u, mi)
        } else if let m = eersteMatch(#"\bom (\d{1,2})\b"#, in: klein), let u = Int(m[1]), u < 24 {
            tijd = (middag(u), 0)
        } else if !woorden.isDisjoint(with: ["vanavond", "tonight"]) {
            tijd = (19, 0)
        }

        // Alleen een tijd ("om 14:00 bellen") betekent vandaag, of morgen als dat al voorbij is.
        if dag == nil, let t = tijd, let vandaagOm = kal.date(bySettingHour: t.uur, minute: t.minuut, second: 0, of: vandaag) {
            return Voorstel(dag: vandaagOm > nu ? vandaagOm : kal.date(byAdding: .day, value: 1, to: vandaagOm)!, heeftTijd: true)
        }
        guard let gevonden = dag else { return nil }
        if let t = tijd, let metTijd = kal.date(bySettingHour: t.uur, minute: t.minuut, second: 0, of: gevonden) {
            return Voorstel(dag: metTijd, heeftTijd: true)
        }
        return Voorstel(dag: gevonden, heeftTijd: false)
    }

    static func eersteMatch(_ patroon: String, in tekst: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: patroon),
              let m = re.firstMatch(in: tekst, range: NSRange(tekst.startIndex..., in: tekst)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: tekst).map { String(tekst[$0]) } ?? ""
        }
    }
}
