import Foundation

/// Hiragana en katakana leren: rijen (a, ka, sa…), een teken en zijn uitspraak in romaji.
enum Kana {
    enum Schrift: String, CaseIterable { case hiragana, katakana }

    struct Teken: Equatable, Hashable {
        var kana: String
        var romaji: String
    }

    struct Rij: Equatable {
        var naam: String      // "a", "ka", …
        var tekens: [Teken]   // in hiragana
    }

    private static func rij(_ naam: String, _ kana: String, _ romaji: String) -> Rij {
        Rij(naam: naam, tekens: zip(kana.map(String.init), romaji.split(separator: " ").map(String.init)).map { Teken(kana: $0, romaji: $1) })
    }

    /// De 46 basistekens, daarna die met tenten (゛) en rondje (゜).
    static let rijen: [Rij] = [
        rij("a", "あいうえお", "a i u e o"), rij("ka", "かきくけこ", "ka ki ku ke ko"), rij("sa", "さしすせそ", "sa shi su se so"),
        rij("ta", "たちつてと", "ta chi tsu te to"), rij("na", "なにぬねの", "na ni nu ne no"), rij("ha", "はひふへほ", "ha hi fu he ho"),
        rij("ma", "まみむめも", "ma mi mu me mo"), rij("ya", "やゆよ", "ya yu yo"), rij("ra", "らりるれろ", "ra ri ru re ro"),
        rij("wa", "わをん", "wa wo n"),
        rij("ga", "がぎぐげご", "ga gi gu ge go"), rij("za", "ざじずぜぞ", "za ji zu ze zo"), rij("da", "だぢづでど", "da ji zu de do"),
        rij("ba", "ばびぶべぼ", "ba bi bu be bo"), rij("pa", "ぱぴぷぺぽ", "pa pi pu pe po"),
    ]

    /// Katakana ligt in Unicode precies 0x60 verder dan hiragana.
    static func inSchrift(_ t: Teken, _ schrift: Schrift) -> Teken {
        guard schrift == .katakana else { return t }
        let kata = String(String.UnicodeScalarView(t.kana.unicodeScalars.compactMap { Unicode.Scalar($0.value + 0x60) }))
        return Teken(kana: kata, romaji: t.romaji)
    }

    static func tekens(rijen namen: Set<String>, schrift: Schrift) -> [Teken] {
        rijen.filter { namen.contains($0.naam) }.flatMap(\.tekens).map { inSchrift($0, schrift) }
    }

    /// Antwoordknoppen: het goede romaji plus andere uit de pool, allemaal verschillend, door elkaar.
    static func opties<R: RandomNumberGenerator>(voor goed: Teken, pool: [Teken], aantal: Int = 4, rng: inout R) -> [String] {
        var andere = Array(Set(pool.map(\.romaji) + rijen.flatMap(\.tekens).map(\.romaji)).subtracting([goed.romaji]))
        andere.sort()
        andere.shuffle(using: &rng)
        // eerst uit de rijen die je oefent, die lijken het meest op elkaar
        let dichtbij = andere.filter { r in pool.contains { $0.romaji == r } }
        let rest = andere.filter { r in !pool.contains { $0.romaji == r } }
        var uit = Array((dichtbij + rest).prefix(aantal - 1)) + [goed.romaji]
        uit.shuffle(using: &rng)
        return uit
    }
}
