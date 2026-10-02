import Foundation

/// Kanji oefenen met woorden uit je eigen Japanse leesstukjes: het woord, de lezing in hiragana en (als bekend) de betekenis.
enum Kanji {
    struct Kaart: Equatable, Hashable {
        var woord: String
        var lezing: String
        var betekenis: String
    }

    static func heeftKanji(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    /// Unieke woorden met kanji uit de tekst, in volgorde van voorkomen, met hun lezing.
    /// `betekenissen`: woord → Nederlandse betekenis (de woordenlijst van het stukje), mag leeg zijn.
    static func kaarten(uit tekst: String, betekenissen: [String: String] = [:]) -> [Kaart] {
        var gezien = Set<String>()
        return Woorden.knip(tekst, taal: "ja").compactMap { w in
            guard heeftKanji(w.tekst), gezien.insert(w.tekst).inserted,
                  let lezing = Woorden.lezing(w.tekst, taal: "ja"), lezing != w.tekst else { return nil }
            return Kaart(woord: w.tekst, lezing: lezing, betekenis: betekenissen[w.tekst.lowercased()] ?? "")
        }
    }

    /// De goede lezing plus andere lezingen uit de stapel, allemaal verschillend, door elkaar.
    static func opties<R: RandomNumberGenerator>(voor goed: Kaart, uit alle: [Kaart], aantal: Int = 4, rng: inout R) -> [String] {
        var andere = Array(Set(alle.map(\.lezing)).subtracting([goed.lezing])).sorted()
        andere.shuffle(using: &rng)
        var uit = Array(andere.prefix(aantal - 1)) + [goed.lezing]
        uit.shuffle(using: &rng)
        return uit
    }
}
