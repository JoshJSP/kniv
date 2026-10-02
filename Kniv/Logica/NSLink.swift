import Foundation

/// Link naar de NS-reisplanner. Getest in een browser (03-10-2026): kale stationsnamen ("Tilburg") werken,
/// "Station Tilburg" niet; daarom eerst schoonmaken.
enum NSLink {
    /// Kaarten noemt stations "Station Tilburg", "Breda station" of "Treinstation Oss"; NS wil "Tilburg".
    static func stationsnaam(_ naam: String) -> String {
        let weg: Set<String> = ["station", "treinstation", "ns", "railway", "train"]
        let woorden = naam.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "(" || $0 == ")" })
            .map(String.init)
            .filter { !weg.contains($0.lowercased()) }
        return woorden.joined(separator: " ")
    }

    /// https://www.ns.nl/reisplanner/#/?vertrek=…&vertrektype=treinstation&aankomst=…&aankomsttype=treinstation&type=vertrek&tijd=2026-10-05T09:00
    static func url(van: String, naar: String, vertrek: Date, tijdzone: TimeZone = TimeZone(identifier: "Europe/Amsterdam")!) -> URL? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tijdzone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let veilig = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func code(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: veilig) ?? s }
        let van = stationsnaam(van), naar = stationsnaam(naar)
        guard !van.isEmpty, !naar.isEmpty, van.lowercased() != naar.lowercased() else { return nil }
        return URL(string: "https://www.ns.nl/reisplanner/#/?vertrek=\(code(van))&vertrektype=treinstation&aankomst=\(code(naar))"
                   + "&aankomsttype=treinstation&type=vertrek&tijd=\(f.string(from: vertrek))")
    }
}
