import Foundation

/// Ziet een timer in een notitie: "over 20 min oven uit" → ("Oven uit", 1200 s).
enum TimerParser {
    static let vulwoorden: Set<String> = ["over", "timer", "na", "in", "voor", "zet", "een"]

    static func vind(in tekst: String) -> (naam: String, seconden: Int)? {
        let patroon = #"\b(\d{1,3})\s*(minuten|minuut|min|m|uur|u|seconden|sec|s)\b"#
        guard let m = Herinnering.eersteMatch(patroon, in: tekst.lowercased()), let n = Int(m[1]), n > 0 else { return nil }
        let factor = m[2].hasPrefix("u") ? 3600 : m[2].hasPrefix("s") ? 1 : 60
        let seconden = n * factor
        guard seconden <= 24 * 3600 else { return nil }

        let zonderDuur = tekst.replacingOccurrences(of: patroon, with: " ", options: [.regularExpression, .caseInsensitive])
        let woorden = zonderDuur.split(whereSeparator: \.isWhitespace).filter { !vulwoorden.contains($0.lowercased()) }
        let naam = woorden.joined(separator: " ")
        return (naam.isEmpty ? "Timer" : naam.prefix(1).uppercased() + naam.dropFirst(), seconden)
    }

    static func klok(_ seconden: TimeInterval) -> String {
        let s = max(0, Int(seconden.rounded(.up)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
