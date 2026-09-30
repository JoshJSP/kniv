import Foundation
import NaturalLanguage

/// Een aantikbaar woord met zijn plek in de tekst.
struct Woord: Equatable {
    let tekst: String
    let bereik: Range<String.Index>
}

/// Tekst knippen in woorden en zinnen (ook Japans en Chinees, zonder spaties), en de lezing van een woord.
enum Woorden {
    /// Woorden zonder getallen, symbolen en emoji; leestekens telt NLTokenizer al niet mee.
    static func knip(_ tekst: String, taal code: String) -> [Woord] {
        let knipper = NLTokenizer(unit: .word)
        knipper.string = tekst
        knipper.setLanguage(NLLanguage(rawValue: code))
        var woorden: [Woord] = []
        knipper.enumerateTokens(in: tekst.startIndex..<tekst.endIndex) { bereik, soort in
            if soort.isDisjoint(with: [.numeric, .symbolic, .emoji]) {
                woorden.append(Woord(tekst: String(tekst[bereik]), bereik: bereik))
            }
            return true
        }
        return woorden
    }

    /// De zin waarin het bereik staat, getrimd.
    static func zin(om bereik: Range<String.Index>, in tekst: String) -> String {
        guard bereik.lowerBound < tekst.endIndex else { return "" }
        let knipper = NLTokenizer(unit: .sentence)
        knipper.string = tekst
        return String(tekst[knipper.tokenRange(at: bereik.lowerBound)]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lezing: Japans in hiragana, Chinees in pinyin. Nil voor andere talen of als het niets toevoegt.
    static func lezing(_ woord: String, taal code: String) -> String? {
        guard code == "ja" || code == "zh" else { return nil }
        let cf = woord as CFString
        let knipper = CFStringTokenizerCreate(kCFAllocatorDefault, cf, CFRangeMake(0, CFStringGetLength(cf)),
                                              kCFStringTokenizerUnitWord, Locale(identifier: code) as CFLocale)
        var delen: [String] = []
        while !CFStringTokenizerAdvanceToNextToken(knipper).isEmpty {
            if let deel = CFStringTokenizerCopyCurrentTokenAttribute(knipper, kCFStringTokenizerAttributeLatinTranscription) as? String {
                delen.append(deel)
            }
        }
        guard !delen.isEmpty else { return nil }
        let uitkomst = code == "ja"
            ? delen.joined().applyingTransform(.latinToHiragana, reverse: false)
            : delen.joined(separator: " ")
        // Katakana → hiragana is geen lezing: dan staat er hetzelfde woord in een ander schrift.
        guard let lezing = uitkomst, !lezing.isEmpty, lezing != woord,
              lezing != woord.applyingTransform(.hiraganaToKatakana, reverse: true) else { return nil }
        return lezing
    }
}
