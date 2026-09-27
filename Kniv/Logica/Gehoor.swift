import Foundation

/// Hoe lang je veilig kunt blijven bij een geluidsniveau (NIOSH: 85 dB mag 8 uur, elke 3 dB erbij halveert de tijd).
enum Gehoor {
    static func veiligeMinuten(bij db: Double) -> Double {
        guard db >= 80 else { return .infinity }
        return 8 * 60 / pow(2, (db - 85) / 3)
    }

    /// Welk deel van je dagelijkse "geluidsportie" je al op hebt, na een reeks metingen (dB, seconden).
    static func portie(_ metingen: [(db: Double, seconden: Double)]) -> Double {
        metingen.reduce(0) { som, m in som + (m.db >= 80 ? m.seconden / 60 / veiligeMinuten(bij: m.db) : 0) }
    }
}
