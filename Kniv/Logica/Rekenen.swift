import Foundation

// MARK: afrekenen in een pot

enum Afrekenen {
    struct Betaling: Equatable {
        let van: String
        let naar: String
        let bedrag: Double
    }

    /// Saldo per persoon: positief = krijgt geld terug, negatief = moet betalen.
    static func saldi(_ uitgaven: [(betaaldDoor: String, bedrag: Double, voor: [String])]) -> [String: Double] {
        var s: [String: Double] = [:]
        for u in uitgaven where !u.voor.isEmpty {
            s[u.betaaldDoor, default: 0] += u.bedrag
            for p in u.voor { s[p, default: 0] -= u.bedrag / Double(u.voor.count) }
        }
        return s
    }

    /// Grootste schuldenaar betaalt steeds de grootste ontvanger; dat geeft (bijna altijd) het minste aantal overboekingen.
    static func minsteBetalingen(_ saldi: [String: Double]) -> [Betaling] {
        var krijgers = saldi.filter { $0.value > 0.005 }.map { ($0.key, $0.value) }.sorted { ($0.1, $1.0) > ($1.1, $0.0) }
        var betalers = saldi.filter { $0.value < -0.005 }.map { ($0.key, -$0.value) }.sorted { ($0.1, $1.0) > ($1.1, $0.0) }
        var uit: [Betaling] = []
        var i = 0, j = 0
        while i < betalers.count && j < krijgers.count {
            let b = min(betalers[i].1, krijgers[j].1)
            uit.append(Betaling(van: betalers[i].0, naar: krijgers[j].0, bedrag: (b * 100).rounded() / 100))
            betalers[i].1 -= b
            krijgers[j].1 -= b
            if betalers[i].1 < 0.005 { i += 1 }
            if krijgers[j].1 < 0.005 { j += 1 }
        }
        return uit
    }
}

// MARK: bonnetjes

enum BonParser {
    struct Regel: Equatable {
        let naam: String
        let prijs: Double
    }

    static let overslaan = ["totaal", "total", "subtotaal", "btw", "pin", "contant", "wisselgeld", "te betalen", "betaald",
                            "bankpas", "vat", "change", "cash", "visa", "mastercard", "maestro", "saldo", "bonuskaart"]

    static func regels(_ tekst: String) -> [Regel] {
        tekst.components(separatedBy: .newlines).compactMap { r in
            let regel = r.trimmingCharacters(in: .whitespaces)
            let klein = regel.lowercased()
            guard !overslaan.contains(where: klein.contains),
                  let m = Herinnering.eersteMatch(#"^(.*?\p{L}.*?)\s+(?:€\s*)?(-?\d{1,4}[.,]\d{2})\s*\p{L}?$"#, in: regel),
                  let prijs = bedrag(m[2]) else { return nil }
            return Regel(naam: m[1].trimmingCharacters(in: .whitespaces), prijs: prijs)
        }
    }

    static func lijktBon(_ tekst: String) -> Bool {
        let klein = tekst.lowercased()
        return regels(tekst).count >= 2 && ["totaal", "total", "btw", "te betalen", "pin"].contains(where: klein.contains)
    }

    static func bedrag(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    /// Het totaalbedrag van een bon: de regel met "totaal"/"te betalen", anders de som van de regels.
    static func totaal(_ tekst: String) -> Double? {
        for regel in tekst.components(separatedBy: .newlines) {
            let klein = regel.lowercased()
            guard ["totaal", "total", "te betalen"].contains(where: klein.contains), !klein.contains("subtotaal"),
                  let m = Herinnering.eersteMatch(#"(-?\d{1,5}[.,]\d{2})\s*$"#, in: regel.trimmingCharacters(in: .whitespaces)) else { continue }
            return bedrag(m[1])
        }
        let som = regels(tekst).reduce(0) { $0 + $1.prijs }
        return som > 0 ? som : nil
    }
}

// MARK: omzetten: "3 cups bloem", "45 usd", "30% korting op 89", "10 km in mijl"

enum Omzetter {
    static var locale = Locale.current

    struct Soort {
        let namen: [String]
        let eenheid: Dimension
        let doel: String      // standaard omzetten naar deze naam
        let label: String
    }

    static let soorten: [Soort] = [
        Soort(namen: ["mijl", "mile", "miles", "mi"], eenheid: UnitLength.miles, doel: "km", label: "mijl"),
        Soort(namen: ["km", "kilometer"], eenheid: UnitLength.kilometers, doel: "mijl", label: "km"),
        Soort(namen: ["m", "meter"], eenheid: UnitLength.meters, doel: "ft", label: "m"),
        Soort(namen: ["cm"], eenheid: UnitLength.centimeters, doel: "inch", label: "cm"),
        Soort(namen: ["ft", "feet", "foot", "voet"], eenheid: UnitLength.feet, doel: "m", label: "ft"),
        Soort(namen: ["inch", "inches", "\""], eenheid: UnitLength.inches, doel: "cm", label: "inch"),
        Soort(namen: ["yard", "yards", "yd"], eenheid: UnitLength.yards, doel: "m", label: "yd"),
        Soort(namen: ["lb", "lbs", "pond", "pound", "pounds"], eenheid: UnitMass.pounds, doel: "kg", label: "lb"),
        Soort(namen: ["oz", "ounce", "ounces"], eenheid: UnitMass.ounces, doel: "g", label: "oz"),
        Soort(namen: ["stone", "st"], eenheid: UnitMass.stones, doel: "kg", label: "stone"),
        Soort(namen: ["kg", "kilo"], eenheid: UnitMass.kilograms, doel: "lb", label: "kg"),
        Soort(namen: ["g", "gram"], eenheid: UnitMass.grams, doel: "oz", label: "g"),
        Soort(namen: ["cup", "cups", "kop", "kopjes"], eenheid: UnitVolume.cups, doel: "ml", label: "cups"),
        Soort(namen: ["tbsp", "el", "eetlepel", "eetlepels"], eenheid: UnitVolume.tablespoons, doel: "ml", label: "el"),
        Soort(namen: ["tsp", "tl", "theelepel", "theelepels"], eenheid: UnitVolume.teaspoons, doel: "ml", label: "tl"),
        Soort(namen: ["gallon", "gallons", "gal"], eenheid: UnitVolume.gallons, doel: "l", label: "gallon"),
        Soort(namen: ["l", "liter"], eenheid: UnitVolume.liters, doel: "gallon", label: "l"),
        Soort(namen: ["ml"], eenheid: UnitVolume.milliliters, doel: "cups", label: "ml"),
        Soort(namen: ["f", "°f", "fahrenheit"], eenheid: UnitTemperature.fahrenheit, doel: "c", label: "°F"),
        Soort(namen: ["c", "°c", "celsius"], eenheid: UnitTemperature.celsius, doel: "f", label: "°C"),
        Soort(namen: ["mph"], eenheid: UnitSpeed.milesPerHour, doel: "km/h", label: "mph"),
        Soort(namen: ["km/h", "kmh", "km/u"], eenheid: UnitSpeed.kilometersPerHour, doel: "mph", label: "km/h"),
        Soort(namen: ["gb"], eenheid: UnitInformationStorage.gigabytes, doel: "mb", label: "GB"),
        Soort(namen: ["mb"], eenheid: UnitInformationStorage.megabytes, doel: "gb", label: "MB"),
        Soort(namen: ["tb"], eenheid: UnitInformationStorage.terabytes, doel: "gb", label: "TB"),
        Soort(namen: ["mbps", "mbit", "mbit/s"], eenheid: UnitInformationStorage.megabits, doel: "mb", label: "Mbps"),
    ]

    /// Gram per US-cup, zodat "3 cups bloem" ook in gram kan.
    static let dichtheid = ["bloem": 125.0, "flour": 125, "suiker": 200, "sugar": 200, "boter": 227, "butter": 227,
                            "rijst": 185, "rice": 185, "havermout": 90, "oats": 90, "cacao": 100, "melk": 240, "milk": 240]

    static let symbolen = ["$": "USD", "£": "GBP", "¥": "JPY", "₺": "TRY", "kr": "SEK", "zł": "PLN", "chf": "CHF"]

    static func reken(_ invoer: String, koersen: [String: Double] = [:], nu: Date = Date()) -> String? {
        let klein = invoer.lowercased().trimmingCharacters(in: .whitespaces)
        return tijd(klein, nu: nu) ?? procent(klein) ?? valuta(klein, koersen) ?? eenheid(klein)
    }

    // MARK: rekenen met tijd: "14:35 + 2u50", "9:15 tot 17:30", "dagen tot 25 dec"

    static func tijd(_ t: String, nu: Date) -> String? {
        if let m = Herinnering.eersteMatch(#"^(?:dagen tot|hoe lang tot|days until|how long until)\s+(.+)$"#, in: t),
           let doel = Herinnering.vind(in: m[1], nu: nu) {
            let kal = Calendar.current
            let dagen = kal.dateComponents([.day], from: kal.startOfDay(for: nu), to: kal.startOfDay(for: doel.dag)).day ?? 0
            return dagen == 0 ? "Dat is vandaag!" : dagen >= 14 ? "Nog \(dagen) dagen (\(dagen / 7) weken en \(dagen % 7) dagen)" : "Nog \(dagen) dagen"
        }
        let klok = #"(\d{1,2}):(\d{2})"#
        if let m = Herinnering.eersteMatch("^" + klok + #"\s*(?:tot|-|–|to|until)\s*"# + klok + "$", in: t),
           let a = minuten(m[1], m[2]), let b = minuten(m[3], m[4]) {
            let d = (b - a + 1440) % 1440
            return "\(m[1]):\(m[2]) tot \(m[3]):\(m[4]) = \(duurTekst(d)) (\(mooi(Double(d) / 60)) uur)"
        }
        if let m = Herinnering.eersteMatch("^" + klok + #"\s*([+-])\s*(.+)$"#, in: t),
           let a = minuten(m[1], m[2]), let d = duur(m[4]) {
            let som = a + (m[3] == "+" ? d : -d)
            let dagen = Int((Double(som) / 1440).rounded(.down))
            let r = som - dagen * 1440
            let extra = dagen > 0 ? " (volgende dag)" : dagen < 0 ? " (dag ervoor)" : ""
            return "\(m[1]):\(m[2]) \(m[3]) \(duurTekst(d)) = \(r / 60):\(String(format: "%02d", r % 60))\(extra)"
        }
        return nil
    }

    static func minuten(_ u: String, _ m: String) -> Int? {
        guard let u = Int(u), let m = Int(m), u < 24, m < 60 else { return nil }
        return u * 60 + m
    }

    /// "2u50", "2:50", "45 min", "1,5 uur", "2h" → minuten.
    static func duur(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let m = Herinnering.eersteMatch(#"^(\d+):(\d{2})$"#, in: t), let u = Int(m[1]), let mi = Int(m[2]) { return u * 60 + mi }
        if let m = Herinnering.eersteMatch(#"^(\d+(?:[.,]\d+)?)\s*(?:u|uur|h|hours?)\s*(?:(\d+)\s*(?:m|min|minuten|minutes)?)?$"#, in: t),
           let u = getal(m[1]) { return Int((u * 60).rounded()) + (Int(m[2]) ?? 0) }
        if let m = Herinnering.eersteMatch(#"^(\d+)\s*(?:m|min|minuten|minutes)$"#, in: t) { return Int(m[1]) }
        return nil
    }

    static func duurTekst(_ min: Int) -> String {
        min < 60 ? "\(min) min" : min % 60 == 0 ? "\(min / 60) u" : "\(min / 60) u \(min % 60) min"
    }

    static func getal(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    static func mooi(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = v.magnitude < 10 ? 2 : v.magnitude < 100 ? 1 : 0
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    static func euro(_ v: Double, _ code: String = "EUR") -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .currency
        f.currencyCode = code
        return f.string(from: NSNumber(value: v)) ?? "\(v) \(code)"
    }

    private static let num = #"(-?\d+(?:[.,]\d+)?)"#

    static func procent(_ t: String) -> String? {
        guard let m = Herinnering.eersteMatch(num + #"\s*%\s*(korting|off)?\s*(?:op|van|of|on)\s*€?\s*"# + num, in: t),
              let p = getal(m[1]), let b = getal(m[3]) else { return nil }
        let deel = b * p / 100
        return m[2].isEmpty ? "\(mooi(p))% van \(mooi(b)) = \(mooi(deel))"
            : "Je betaalt \(euro(b - deel)) en bespaart \(euro(deel))"
    }

    static func valuta(_ t: String, _ koersen: [String: Double]) -> String? {
        let codes = Set(koersen.keys.map { $0.lowercased() })
        var bedrag: Double?
        var code: String?
        if let m = Herinnering.eersteMatch(num + #"\s*([a-z]{3})\b"#, in: t), codes.contains(m[2]) || m[2] == "eur" {
            bedrag = getal(m[1]); code = m[2].uppercased()
        } else if let m = Herinnering.eersteMatch(#"(\$|£|¥|₺|€)\s*"# + num, in: t) {
            bedrag = getal(m[2]); code = m[1] == "€" ? "EUR" : symbolen[m[1]]
        } else if let m = Herinnering.eersteMatch(num + #"\s*(\$|£|¥|₺|€|kr|zł)"#, in: t) {
            bedrag = getal(m[1]); code = m[2] == "€" ? "EUR" : symbolen[m[2]]
        }
        guard let bedrag, let code else { return nil }
        if code == "EUR" {
            guard let m = Herinnering.eersteMatch(#"(?:in|naar|to)\s+([a-z]{3})\b"#, in: t), let r = koersen[m[1].uppercased()] else { return nil }
            return "\(euro(bedrag)) ≈ \(euro(bedrag * r, m[1].uppercased()))"
        }
        guard let r = koersen[code], r > 0 else { return nil }
        return "\(euro(bedrag, code)) ≈ \(euro(bedrag / r))"
    }

    static func soort(_ naam: String) -> Soort? { soorten.first { $0.namen.contains(naam) } }

    static func eenheid(_ t: String) -> String? {
        guard let m = Herinnering.eersteMatch(num + #"\s*(°?[a-z]+(?:/[a-z]+)?|")"#, in: t),
              let waarde = getal(m[1]), let van = soort(m[2]) else { return nil }
        let gevraagd = Herinnering.eersteMatch(#"(?:in|naar|to)\s+(°?[a-z]+(?:/[a-z]+)?)\s*$"#, in: t).flatMap { soort($0[1]) }
        guard let naar = gevraagd ?? soort(van.doel), type(of: naar.eenheid) == type(of: van.eenheid) else { return nil }
        let uitkomst = Measurement(value: waarde, unit: van.eenheid).converted(to: naar.eenheid).value
        var tekst = "\(mooi(waarde)) \(van.label) = \(mooi(uitkomst)) \(naar.label)"
        if van.eenheid is UnitVolume, let stof = dichtheid.first(where: { t.contains($0.key) }) {
            let cups = Measurement(value: waarde, unit: van.eenheid).converted(to: UnitVolume.cups).value
            tekst += " ≈ \(mooi(cups * stof.value)) g \(stof.key)"
        }
        return tekst
    }
}

// MARK: fooi naar sterren

/// Sterren (0–5) voor eten, drinken en service; nil = niet van toepassing en telt niet mee.
/// Service weegt het zwaarst, want daar is fooi vooral voor. Gemiddelde sterren → percentage volgens een
/// Nederlandse maatstaf: 0★ niks, 3★ netjes (8%), 5★ geweldig (15%).
enum Fooi {
    static let gewicht = (eten: 1.5, drinken: 1.0, service: 2.0)
    static let schaal: [Double] = [0, 2, 5, 8, 10, 15]    // procent bij 0...5 sterren

    static func procent(eten: Int?, drinken: Int?, service: Int?) -> Double? {
        let delen = [(eten, gewicht.eten), (drinken, gewicht.drinken), (service, gewicht.service)]
            .compactMap { s, g in s.map { (Double(min(max($0, 0), 5)), g) } }
        guard !delen.isEmpty else { return nil }
        let sterren = delen.reduce(0) { $0 + $1.0 * $1.1 } / delen.reduce(0) { $0 + $1.1 }
        let laag = Int(sterren.rounded(.down))
        guard laag < 5 else { return schaal[5] }
        return schaal[laag] + (schaal[laag + 1] - schaal[laag]) * (sterren - Double(laag))
    }

    /// Fooi en een totaal afgerond op hele of halve euro's (zo rond je fooi meestal af), nooit onder de prijs.
    static func advies(prijs: Double, procent: Double) -> (fooi: Double, totaal: Double) {
        guard procent > 0 else { return (0, prijs) }
        let ruw = prijs * (1 + procent / 100)
        let totaal = max((ruw * 2 - 1e-9).rounded(.up) / 2, prijs)      // naar boven, anders wordt een kleine fooi €0
        return (totaal - prijs, totaal)
    }
}
