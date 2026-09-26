import Foundation

/// Herkent afvinklijstjes in getypte tekst: regels die met "- ", "• " of "[ ] " beginnen.
enum NotitieParser {
    static let voorvoegsels = ["- ", "• ", "* ", "[ ] ", "[] "]

    static func ontleed(_ tekst: String) -> (rest: String, items: [String]) {
        var rest: [String] = []
        var items: [String] = []
        for regel in tekst.components(separatedBy: .newlines) {
            let kaal = regel.trimmingCharacters(in: .whitespaces)
            if voorvoegsels.contains(kaal + " ") { continue }  // leeg streepje: overslaan
            if let item = lijstItem(kaal) {
                items.append(item)
            } else {
                rest.append(regel)
            }
        }
        return (rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), items)
    }

    static func lijstItem(_ regel: String) -> String? {
        guard let p = voorvoegsels.first(where: { regel.hasPrefix($0) }) else { return nil }
        let item = regel.dropFirst(p.count).trimmingCharacters(in: .whitespaces)
        return item.isEmpty ? nil : item
    }
}
