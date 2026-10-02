import Foundation

/// Een rondje kaartjes: "wist ik" haalt het kaartje uit dit rondje, "nog eens" legt het achteraan.
/// Geen punten of reeksen; het rondje is klaar als alles één keer gekend is.
struct Stapel<Kaart: Equatable>: Equatable {
    private(set) var rij: [Kaart]

    init(_ kaarten: [Kaart]) { rij = kaarten }

    var boven: Kaart? { rij.first }
    var over: Int { rij.count }
    var klaar: Bool { rij.isEmpty }

    mutating func wist() { if !rij.isEmpty { rij.removeFirst() } }

    /// Achteraan, maar bij een grote stapel niet helemaal: na een paar andere kaartjes komt hij terug.
    mutating func nogEens(naAantal: Int = 4) {
        guard !rij.isEmpty else { return }
        let k = rij.removeFirst()
        rij.insert(k, at: min(naAantal, rij.count))
    }
}
