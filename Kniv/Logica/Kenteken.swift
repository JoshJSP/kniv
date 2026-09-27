import Foundation

/// Nederlandse kentekens: opschonen, mooi schrijven en terugvinden in herkende tekst.
enum Kenteken {
    /// "gz-738-t" → "GZ738T"; nil als het geen 6 tekens letters/cijfers zijn.
    static func normaal(_ tekst: String) -> String? {
        let schoon = tekst.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return schoon.count == 6 ? schoon : nil
    }

    /// "GZ738T" → "GZ-738-T": streepjes waar letters en cijfers wisselen (of 2-2-2 als dat niet gebeurt).
    static func mooi(_ k: String) -> String {
        let tekens = Array(k)
        var uit = ""
        for (i, c) in tekens.enumerated() {
            if i > 0, c.isLetter != tekens[i - 1].isLetter { uit.append("-") }
            uit.append(c)
        }
        if !uit.contains("-") || uit.filter({ $0 == "-" }).count == 1 {
            uit = [0, 2, 4].map { String(tekens[$0..<$0 + 2]) }.joined(separator: "-")
        }
        return uit
    }

    /// Zoekt een kenteken in tekst van de camera, zoals "GZ-738-T" of "12-ABC-3".
    static func vind(in tekst: String) -> String? {
        let patroon = #"\b([A-Z0-9]{1,3})[\s-]([A-Z0-9]{2,3})[\s-]([A-Z0-9]{1,3})\b"#
        guard let m = Herinnering.eersteMatch(patroon, in: tekst.uppercased()) else { return nil }
        return normaal(m[1] + m[2] + m[3])
    }

    /// RDW-datum "20270926" → Date.
    static func datum(_ s: String?) -> Date? {
        guard let s, s.count == 8, let j = Int(s.prefix(4)), let m = Int(s.dropFirst(4).prefix(2)), let d = Int(s.suffix(2)) else { return nil }
        return Calendar.current.date(from: DateComponents(year: j, month: m, day: d))
    }
}
