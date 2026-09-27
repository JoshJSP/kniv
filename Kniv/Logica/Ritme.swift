import Foundation

/// Leert op welke uren je dingen afvinkt en focust, per weekdag. Een herinnering zonder tijd valt dan op jouw moment.
enum Ritme {
    static let sleutel = "ritme"

    static func vak(_ datum: Date) -> String {
        let c = Calendar.current.dateComponents([.weekday, .hour], from: datum)
        return "\(c.weekday ?? 1)-\(c.hour ?? 0)"
    }

    static func noteer(_ datum: Date = Date(), in opslag: UserDefaults = .standard) {
        var h = opslag.dictionary(forKey: sleutel) as? [String: Int] ?? [:]
        h[vak(datum), default: 0] += 1
        opslag.set(h, forKey: sleutel)
    }

    /// Het uur (8–21) waarop je op deze weekdag het vaakst iets doet, als er genoeg gegevens zijn (minstens 3 keer).
    static func voorkeur(uit histogram: [String: Int], weekdag: Int) -> Int? {
        let kandidaten = (8...21).compactMap { uur in histogram["\(weekdag)-\(uur)"].map { (uur, $0) } }
        guard let beste = kandidaten.max(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 > $1.0 }), beste.1 >= 3 else { return nil }
        return beste.0
    }

    static func voorkeur(voor dag: Date, in opslag: UserDefaults = .standard) -> Int? {
        voorkeur(uit: opslag.dictionary(forKey: sleutel) as? [String: Int] ?? [:],
                 weekdag: Calendar.current.component(.weekday, from: dag))
    }
}
