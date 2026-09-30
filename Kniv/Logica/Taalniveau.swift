import Foundation

/// ERK-niveau in halve stappen (A1, A1+, … C1). Een stap is de index in `codes`.
enum Taalniveau {
    static let codes = ["A1", "A1+", "A2", "A2+", "B1", "B1+", "B2", "B2+", "C1"]

    /// Code bij een stap, begrensd op A1…C1.
    static func code(_ stap: Int) -> String { codes[begrensd(stap)] }

    enum Oordeel { case teMakkelijk, precies, teMoeilijk }

    /// Na een stukje: te makkelijk een halve stap omhoog, te moeilijk een halve stap omlaag.
    static func na(_ oordeel: Oordeel, stap: Int) -> Int {
        switch oordeel {
        case .teMakkelijk: return begrensd(stap + 1)
        case .precies: return begrensd(stap)
        case .teMoeilijk: return begrensd(stap - 1)
        }
    }

    /// De vijf hele niveaus om mee te beginnen.
    static let startKeuzes: [(code: String, stap: Int)] = [("A1", 0), ("A2", 2), ("B1", 4), ("B2", 6), ("C1", 8)]

    private static func begrensd(_ stap: Int) -> Int { min(max(stap, 0), codes.count - 1) }
}
