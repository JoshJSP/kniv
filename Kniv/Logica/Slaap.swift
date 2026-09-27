import Foundation

/// Slapen in cycli van 90 minuten, plus ±15 minuten om in slaap te vallen. Wakker worden aan het eind van een cyclus voelt frisser.
enum Slaap {
    static let cyclus: TimeInterval = 90 * 60
    static let inslapen: TimeInterval = 15 * 60

    /// Bedtijden voor een wektijd: 6, 5 en 4 cycli (9, 7,5 en 6 uur slaap).
    static func bedtijden(wakker: Date) -> [(tijd: Date, cycli: Int)] {
        [6, 5, 4].map { (wakker.addingTimeInterval(-Double($0) * cyclus - inslapen), $0) }
    }

    /// Wektijden als je nu gaat slapen.
    static func wektijden(vanaf nu: Date) -> [(tijd: Date, cycli: Int)] {
        [4, 5, 6].map { (nu.addingTimeInterval(inslapen + Double($0) * cyclus), $0) }
    }
}
