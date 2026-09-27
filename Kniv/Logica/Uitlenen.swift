import Foundation

/// "Sam heeft mijn oplader", "boek geleend aan Lisa", "Tom leent mijn fiets" → (wie, wat).
enum Uitlenen {
    static func vind(in tekst: String) -> (wie: String, wat: String)? {
        let t = tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = Herinnering.eersteMatch(#"(?i)^(\p{L}+)\s+(?:heeft|leent)\s+(?:mijn|m'n|me)\s+(.+)$"#, in: t) {
            return (m[1], m[2])
        }
        if let m = Herinnering.eersteMatch(#"(?i)^(?:mijn\s+|m'n\s+)?(.+?)\s+(?:uit)?geleend\s+aan\s+(\p{L}+)$"#, in: t) {
            return (m[2], m[1])
        }
        if let m = Herinnering.eersteMatch(#"(?i)^(\p{L}+)\s+has\s+my\s+(.+)$"#, in: t) {
            return (m[1], m[2])
        }
        return nil
    }
}
