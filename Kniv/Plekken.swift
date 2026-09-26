import CoreLocation
import MapKit
import NaturalLanguage
import SwiftData
import UserNotifications

@Model final class Plek {
    var id: UUID = UUID()
    var naam: String
    var soort: String          // thuis, school, eigen
    var breedte: Double
    var lengte: Double
    var bericht: String = ""

    init(naam: String, soort: String, breedte: Double, lengte: Double, bericht: String = "") {
        self.naam = naam
        self.soort = soort
        self.breedte = breedte
        self.lengte = lengte
        self.bericht = bericht
    }
}

/// Houdt plekken in de gaten (ook als Kniv dicht is) en meldt alleen als er sinds de vorige keer iets nieuws is.
/// iOS bewaakt maximaal 20 gebieden per app: eerst je eigen plekken, de rest gaat naar supermarkten in de buurt.
final class PlekWachter: NSObject, CLLocationManagerDelegate {
    static let shared = PlekWachter()
    private let lm = CLLocationManager()
    private var wacht: CheckedContinuation<CLLocation?, Never>?
    private var laatsteZoektocht = Date.distantPast
    private let opslag = UserDefaults.standard

    var supermarktAan: Bool {
        get { opslag.bool(forKey: "supermarktMeldingen") }
        set { opslag.set(newValue, forKey: "supermarktMeldingen"); start() }
    }

    override init() {
        super.init()
        lm.delegate = self
    }

    /// Bij het opstarten: alleen aan de slag als er iets te bewaken is, zodat Kniv niet zomaar om je locatie vraagt.
    func start() {
        let heeftPlekken = ((try? KnivOpslag.container.mainContext.fetchCount(FetchDescriptor<Plek>())) ?? 0) > 0
        guard heeftPlekken || supermarktAan else { return }
        switch lm.authorizationStatus {
        case .notDetermined: lm.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: lm.requestAlwaysAuthorization()
        default: break
        }
        if supermarktAan { lm.startMonitoringSignificantLocationChanges() } else { lm.stopMonitoringSignificantLocationChanges() }
        herlaadGebieden()
    }

    @MainActor func bewaarHier(naam: String, soort: String, bericht: String = "") async -> Bool {
        if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization() }
        guard let plek = await huidigePlek() else { return false }
        let ctx = KnivOpslag.container.mainContext
        if soort != "eigen", let oud = try? ctx.fetch(FetchDescriptor<Plek>()).filter({ $0.soort == soort }) {
            oud.forEach(ctx.delete)
        }
        ctx.insert(Plek(naam: naam, soort: soort, breedte: plek.coordinate.latitude, lengte: plek.coordinate.longitude, bericht: bericht))
        try? ctx.save()
        start()
        return true
    }

    private func huidigePlek() async -> CLLocation? {
        await withCheckedContinuation { c in
            wacht?.resume(returning: nil)
            wacht = c
            lm.requestLocation()
        }
    }

    func herlaadGebieden() {
        DispatchQueue.main.async { [self] in
            lm.monitoredRegions.forEach(lm.stopMonitoring)
            let plekken = (try? KnivOpslag.container.mainContext.fetch(FetchDescriptor<Plek>())) ?? []
            var gebieden = plekken.prefix(20).map {
                CLCircularRegion(center: CLLocationCoordinate2D(latitude: $0.breedte, longitude: $0.lengte), radius: 120, identifier: "plek.\($0.id)")
            }
            if supermarktAan {
                let winkels = opslag.array(forKey: "supermarkten") as? [[Double]] ?? []
                gebieden += winkels.prefix(20 - gebieden.count).enumerated().map { i, w in
                    CLCircularRegion(center: CLLocationCoordinate2D(latitude: w[0], longitude: w[1]), radius: 100, identifier: "super.\(i)")
                }
            }
            for g in gebieden {
                g.notifyOnEntry = true
                g.notifyOnExit = false
                lm.startMonitoring(for: g)
            }
        }
    }

    private func zoekSupermarkten(rond plek: CLLocation) {
        guard supermarktAan, Date().timeIntervalSince(laatsteZoektocht) > 20 * 60 else { return }
        laatsteZoektocht = Date()
        let vraag = MKLocalPointsOfInterestRequest(center: plek.coordinate, radius: 2500)
        vraag.pointOfInterestFilter = MKPointOfInterestFilter(including: [.foodMarket])
        MKLocalSearch(request: vraag).start { [weak self] antwoord, _ in
            guard let self, let items = antwoord?.mapItems else { return }
            let dichtbij = items
                .compactMap { $0.placemark.location }
                .sorted { $0.distance(from: plek) < $1.distance(from: plek) }
                .prefix(14)
                .map { [$0.coordinate.latitude, $0.coordinate.longitude] }
            self.opslag.set(Array(dichtbij), forKey: "supermarkten")
            self.herlaadGebieden()
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse { m.requestAlwaysAuthorization() }
        if m.authorizationStatus == .authorizedAlways || m.authorizationStatus == .authorizedWhenInUse { herlaadGebieden() }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations plekken: [CLLocation]) {
        guard let plek = plekken.last else { return }
        wacht?.resume(returning: plek)
        wacht = nil
        zoekSupermarkten(rond: plek)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        wacht?.resume(returning: nil)
        wacht = nil
    }

    func locationManager(_ m: CLLocationManager, didEnterRegion gebied: CLRegion) {
        Task { @MainActor in self.meld(gebied.identifier) }
    }

    // MARK: melden

    @MainActor private func meld(_ id: String) {
        let ctx = KnivOpslag.container.mainContext
        let notities = (try? ctx.fetch(FetchDescriptor<Notitie>())) ?? []
        func open(_ bakje: String) -> [String] {
            notities.filter { $0.bakjeNaam == bakje }.flatMap { $0.isLijst ? $0.gesorteerdeItems.map(\.tekst) : [$0.titel] }
        }

        var groep = id
        var titel = "Kniv"
        var regels: [String] = []
        if id.hasPrefix("super.") {
            groep = "super"
            titel = String(localized: "Je bent bij de supermarkt")
            regels = open("Boodschappen")
        } else if let plek = ((try? ctx.fetch(FetchDescriptor<Plek>())) ?? []).first(where: { "plek.\($0.id)" == id }) {
            switch plek.soort {
            case "thuis": titel = String(localized: "Welkom thuis"); regels = open("To-do")
            case "school": titel = String(localized: "Op school"); regels = open("School") + open("To-do")
            default: titel = plek.naam; regels = [plek.bericht]
            }
        }
        regels = regels.filter { !$0.isEmpty }
        guard !regels.isEmpty else { return }

        let inhoud = regels.prefix(4).joined(separator: ", ") + (regels.count > 4 ? " (+\(regels.count - 4))" : "")
        let sleutel = "plekMelding.\(groep)"
        guard opslag.string(forKey: sleutel) != inhoud else { return }   // niets nieuws sinds de vorige keer
        opslag.set(inhoud, forKey: sleutel)

        let bericht = UNMutableNotificationContent()
        bericht.title = titel
        bericht.body = inhoud
        bericht.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: bericht, trigger: nil))
    }
}

// MARK: slim zoeken

enum SlimZoeken {
    /// Notities die over hetzelfde gaan als de zoekvraag, ook zonder dezelfde woorden. Op het toestel zelf.
    static func gelijkend(_ vraag: String, in notities: [Notitie]) -> [Notitie] {
        let herkenner = NLLanguageRecognizer()
        herkenner.processString(vraag)
        let taal = herkenner.dominantLanguage ?? .dutch
        guard let model = NLEmbedding.sentenceEmbedding(for: taal) ?? NLEmbedding.sentenceEmbedding(for: .english) else { return [] }
        return notities.prefix(300)
            .compactMap { n -> (Notitie, Double)? in
                let afstand = model.distance(between: vraag, and: String(n.zoekTekst.prefix(300)))
                return afstand < 0.9 ? (n, afstand) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(6)
            .map(\.0)
    }
}
