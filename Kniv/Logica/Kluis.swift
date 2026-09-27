import Foundation

enum Garantie {
    /// In Nederland mag je minstens twee jaar verwachten dat een aankoop werkt.
    static let jaren = 2

    /// Aankoopdatum van een bon: 27-09-2026, 27/09/26, 27.09.2026. Anders nil.
    static func aankoopdatum(in tekst: String, nu: Date = Date()) -> Date? {
        guard let m = Herinnering.eersteMatch(#"\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})\b"#, in: tekst),
              let d = Int(m[1]), let maand = Int(m[2]), var jaar = Int(m[3]), (1...31).contains(d), (1...12).contains(maand) else { return nil }
        if jaar < 100 { jaar += 2000 }
        guard let datum = Calendar.current.date(from: DateComponents(year: jaar, month: maand, day: d)), datum <= nu else { return nil }
        return datum
    }

    static func tot(_ aankoop: Date) -> Date { Calendar.current.date(byAdding: .year, value: jaren, to: aankoop)! }
}

enum QRInhoud {
    /// WIFI-QR die elke iPhone- en Android-camera snapt. ; , : \ en " moeten ge-escaped worden.
    static func wifi(netwerk: String, wachtwoord: String, beveiliging: String = "WPA") -> String {
        func esc(_ s: String) -> String {
            s.reduce(into: "") { r, c in
                if "\\;,:\"".contains(c) { r.append("\\") }
                r.append(c)
            }
        }
        let t = wachtwoord.isEmpty ? "nopass" : beveiliging
        return "WIFI:T:\(t);S:\(esc(netwerk));P:\(wachtwoord.isEmpty ? "" : esc(wachtwoord));;"
    }
}

enum Kompas {
    /// Richting (graden vanaf het noorden, met de klok mee) van punt a naar punt b.
    static func peiling(van a: (Double, Double), naar b: (Double, Double)) -> Double {
        let (φ1, λ1, φ2, λ2) = (a.0 * .pi / 180, a.1 * .pi / 180, b.0 * .pi / 180, b.1 * .pi / 180)
        let y = sin(λ2 - λ1) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(λ2 - λ1)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
