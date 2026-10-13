import Foundation
import NaturalLanguage

/// Gedeelde tekst of een webpagina als leesstukje in Talen: welke taal is het, en wat is de eigenlijke tekst.
enum Leestaal {
    static let maxTekst = 4000

    /// Taalcode als de tekst lang genoeg is (25+ woorden) en met 80% zekerheid geen Nederlands.
    /// Afrikaans en Fries lijken voor de herkenner op Nederlands; die vallen hier dus soms buiten.
    static func vreemd(_ tekst: String) -> String? {
        guard tekst.split(whereSeparator: \.isWhitespace).count >= 25 else { return nil }
        let herkenner = NLLanguageRecognizer()
        herkenner.processString(tekst)
        guard let (taal, kans) = herkenner.languageHypotheses(withMaximum: 1).first,
              kans > 0.8, taal != .dutch, taal != .undetermined else { return nil }
        // "zh-Hans" → "zh": Talen werkt met de twee-lettercode
        return String(taal.rawValue.prefix { $0 != "-" })
    }

    /// HTML naar platte tekst. Eerst de alinea's (<p>), dat is meestal het artikel; anders alles zonder menu's en scripts.
    // ponytail: regex in plaats van een echte HTML-lezer; pakt bij rommelige sites ook wat menu mee. Upgrade: <article> eerst.
    /// Bytes van een webpagina als tekst. Volgt de tekenset uit de header (Shift_JIS, windows-1251…);
    /// anders UTF-8, ook als het afknippen midden in een teken viel. Latin-1 alleen als laatste redmiddel.
    static func tekst(_ data: Data, tekenset: String?) -> String {
        if let naam = tekenset?.lowercased(), naam != "utf-8", naam != "utf8" {
            let cf = CFStringConvertIANACharSetNameToEncoding(naam as CFString)
            if cf != kCFStringEncodingInvalidId,
               let s = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) { return s }
        }
        for n in 0...3 where data.count > n {
            if let s = String(data: data.dropLast(n), encoding: .utf8) { return s }
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func platteTekst(_ html: String) -> String {
        var h = html
        for blok in ["script", "style", "noscript", "nav", "header", "footer", "aside", "form"] {
            h = h.replacingOccurrences(of: "(?is)<\(blok)\\b.*?</\(blok)>", with: " ", options: .regularExpression)
        }
        let alineas = matches(#"(?is)<p\b[^>]*>(.*?)</p>"#, in: h).map(schoon).filter { $0.count > 40 }
        let tekst = alineas.joined(separator: " ").count >= 200 ? alineas.joined(separator: "\n\n") : schoon(h)
        return String(tekst.prefix(maxTekst))
    }

    private static func schoon(_ html: String) -> String {
        var t = html.replacingOccurrences(of: "(?i)<br\\s*/?>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (code, teken) in [("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                              ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"), ("&hellip;", "…"),
                              ("&auml;", "ä"), ("&ouml;", "ö"), ("&uuml;", "ü"), ("&Auml;", "Ä"), ("&Ouml;", "Ö"), ("&Uuml;", "Ü"),
                              ("&szlig;", "ß"), ("&eacute;", "é"), ("&egrave;", "è"), ("&agrave;", "à"), ("&ccedil;", "ç"), ("&ntilde;", "ñ")] {
            t = t.replacingOccurrences(of: code, with: teken)
        }
        // numerieke tekens: &#233; en &#xE9;
        for m in matches(#"&#(x?[0-9A-Fa-f]+);"#, in: t).reversed() {
            let getal = m.hasPrefix("x") ? UInt32(m.dropFirst(), radix: 16) : UInt32(m)
            if let getal, let s = Unicode.Scalar(getal) { t = t.replacingOccurrences(of: "&#\(m);", with: String(Character(s))) }
        }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Eerste vanggroep van elke treffer.
    private static func matches(_ patroon: String, in tekst: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: patroon) else { return [] }
        return re.matches(in: tekst, range: NSRange(tekst.startIndex..., in: tekst)).compactMap { m in
            Range(m.range(at: 1), in: tekst).map { String(tekst[$0]) }
        }
    }
}
