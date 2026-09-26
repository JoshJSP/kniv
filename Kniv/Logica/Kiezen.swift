import Foundation

enum Rad {
    /// Welk vak staat onder de wijzer bovenaan, als het rad `hoek` graden met de klok mee gedraaid is.
    /// Vak 0 begint bovenaan en de vakken lopen met de klok mee.
    static func vak(hoek: Double, aantal: Int) -> Int {
        guard aantal > 0 else { return 0 }
        let rest = (360 - hoek.truncatingRemainder(dividingBy: 360)).truncatingRemainder(dividingBy: 360)
        let positief = rest < 0 ? rest + 360 : rest
        return min(Int(positief / (360 / Double(aantal))), aantal - 1)
    }

    /// Uitlopen met constante remming: hoek na `t` seconden bij beginsnelheid `snelheid` (graden/s).
    static func hoek(start: Double, snelheid: Double, remming: Double, na t: Double) -> Double {
        let duur = abs(snelheid) / remming
        let tt = min(t, duur)
        let richting: Double = snelheid < 0 ? -1 : 1
        return start + snelheid * tt - richting * 0.5 * remming * tt * tt
    }
}

enum Teams {
    static func verdeel<R: RandomNumberGenerator>(_ namen: [String], in aantal: Int, rng: inout R) -> [[String]] {
        guard aantal > 0 else { return [] }
        var teams = Array(repeating: [String](), count: aantal)
        for (i, naam) in namen.shuffled(using: &rng).enumerated() { teams[i % aantal].append(naam) }
        return teams
    }
}

enum Stemming {
    /// Veegstemmen: per optie het aantal keer "ja". Winnaar = meeste ja; bij gelijkspel allemaal.
    static func ja(_ optie: String, _ stemmen: [String: Set<String>]) -> Int { stemmen.values.filter { $0.contains(optie) }.count }

    static func winnaars(_ stemmen: [String: Set<String>], opties: [String]) -> [String] {
        let hoogste = opties.map { ja($0, stemmen) }.max() ?? 0
        return hoogste == 0 ? [] : opties.filter { ja($0, stemmen) == hoogste }
    }
}
