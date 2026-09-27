import Foundation

/// Tekst naar morse, en naar een reeks aan/uit-stappen voor de zaklamp (in "eenheden": punt = 1).
enum Morse {
    static let tabel: [Character: String] = [
        "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".", "f": "..-.", "g": "--.", "h": "....",
        "i": "..", "j": ".---", "k": "-.-", "l": ".-..", "m": "--", "n": "-.", "o": "---", "p": ".--.",
        "q": "--.-", "r": ".-.", "s": "...", "t": "-", "u": "..-", "v": "...-", "w": ".--", "x": "-..-",
        "y": "-.--", "z": "--..", "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.", ".": ".-.-.-", ",": "--..--",
        "?": "..--..", "!": "-.-.--", "@": ".--.-.", "/": "-..-.", "-": "-....-",
    ]

    /// "sos" → "... --- ..."; woorden gescheiden door " / ". Onbekende tekens vallen weg.
    static func code(_ tekst: String) -> String {
        tekst.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split(separator: " ")
            .map { $0.compactMap { tabel[$0] }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    /// Stappen (aan?, eenheden): punt 1 aan, streep 3 aan, tussen tekens 1 uit, tussen letters 3, tussen woorden 7.
    static func stappen(_ tekst: String) -> [(aan: Bool, eenheden: Int)] {
        var uit: [(aan: Bool, eenheden: Int)] = []
        for (w, woord) in code(tekst).components(separatedBy: " / ").enumerated() {
            if w > 0 { uit.append((false, 7)) }
            for (l, letter) in woord.split(separator: " ").enumerated() {
                if l > 0 { uit.append((false, 3)) }
                for (t, teken) in letter.enumerated() {
                    if t > 0 { uit.append((false, 1)) }
                    uit.append((true, teken == "-" ? 3 : 1))
                }
            }
        }
        return uit
    }
}
