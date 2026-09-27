import Foundation

/// Rekent sommen uit die je in de invoerbalk typt: "12*3+4", "(19,99 + 5) / 3", "2^10", "15% van 80" doet Omzetter.
/// Eigen kleine parser (plus, min, keer, delen, macht, haakjes), dus geen eval en geen verrassingen.
enum Rekenmachine {
    static func uitkomst(_ invoer: String) -> Double? {
        let som = invoer.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: " ", with: "")
        // Alleen iets dat echt een som is: cijfers en minstens één bewerking.
        guard !som.isEmpty, som.allSatisfy({ "0123456789.+-*/^()".contains($0) }),
              // Een min telt alleen met spaties eromheen, anders wordt 06-12345678 een som.
              som.contains(where: { "+*/^".contains($0) }) || invoer.contains(" - "),
              som.contains(where: \.isNumber) else { return nil }
        var p = Parser(tekens: Array(som))
        guard let waarde = p.optelling(), p.i == p.tekens.count, waarde.isFinite else { return nil }
        return waarde
    }

    private struct Parser {
        let tekens: [Character]
        var i = 0

        mutating func optelling() -> Double? {
            guard var links = vermenigvuldiging() else { return nil }
            while i < tekens.count, tekens[i] == "+" || tekens[i] == "-" {
                let op = tekens[i]; i += 1
                guard let rechts = vermenigvuldiging() else { return nil }
                links = op == "+" ? links + rechts : links - rechts
            }
            return links
        }

        mutating func vermenigvuldiging() -> Double? {
            guard var links = macht() else { return nil }
            while i < tekens.count, tekens[i] == "*" || tekens[i] == "/" {
                let op = tekens[i]; i += 1
                guard let rechts = macht() else { return nil }
                if op == "/" && rechts == 0 { return nil }
                links = op == "*" ? links * rechts : links / rechts
            }
            return links
        }

        mutating func macht() -> Double? {
            guard let grond = teken() else { return nil }
            if i < tekens.count, tekens[i] == "^" {
                i += 1
                guard let exp = macht() else { return nil }
                return pow(grond, exp)
            }
            return grond
        }

        mutating func teken() -> Double? {
            if i < tekens.count, tekens[i] == "-" { i += 1; return teken().map { -$0 } }
            if i < tekens.count, tekens[i] == "(" {
                i += 1
                guard let v = optelling(), i < tekens.count, tekens[i] == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while i < tekens.count, tekens[i].isNumber || tekens[i] == "." { i += 1 }
            return i > start ? Double(String(tekens[start..<i])) : nil
        }
    }
}
