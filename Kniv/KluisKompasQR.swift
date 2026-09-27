import CoreLocation
import SwiftData
import SwiftUI

// MARK: Garantiekluis

/// In het notitiescherm bij een bon: bewaar in de kluis, met een seintje een maand voor de garantie afloopt.
struct GarantieSectie: View {
    @Bindable var notitie: Notitie

    var body: some View {
        Section {
            if let tot = notitie.garantieTot {
                LabeledContent("Garantie tot", value: tot.formatted(date: .long, time: .omitted))
                Button("Uit de kluis halen", role: .destructive) {
                    Meldingen.annuleer("garantie.\(notitie.uid)")
                    notitie.garantieTot = nil
                }
            } else {
                Button {
                    let aankoop = Garantie.aankoopdatum(in: notitie.fotoTekst) ?? notitie.gemaakt
                    let tot = Garantie.tot(aankoop)
                    notitie.garantieTot = tot
                    if let seintje = Calendar.current.date(byAdding: .month, value: -1, to: tot), seintje > Date() {
                        Meldingen.plan("garantie.\(notitie.uid)",
                                       String(localized: "De garantie op \(notitie.titel) loopt over een maand af. Nog iets mis mee?"),
                                       na: seintje.timeIntervalSinceNow)
                    }
                } label: { Label("Bewaar in de garantiekluis", systemImage: "lock.shield") }
            }
        } header: {
            Text("Garantie")
        } footer: {
            Text("Je hebt in Nederland minstens twee jaar recht op een product dat werkt. Kniv waarschuwt een maand voordat die tijd om is.")
        }
    }
}

/// In Vastleggen: alle bonnen in de kluis, met hoe lang de garantie nog loopt.
struct KluisRij: View {
    @Query(filter: #Predicate<Notitie> { $0.garantieTot != nil && $0.weggegooid == nil }, sort: \Notitie.gemaakt, order: .reverse) private var bonnen: [Notitie]

    var body: some View {
        if !bonnen.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Garantiekluis", systemImage: "lock.shield").font(.headline)
                ForEach(bonnen) { bon in
                    NavigationLink(value: bon) {
                        HStack {
                            Text(bon.titel).lineLimit(1)
                            Spacer()
                            Text(resterend(bon.garantieTot!)).font(.subheadline).foregroundStyle(kleur(bon.garantieTot!))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .glas(20)
        }
    }

    private func resterend(_ tot: Date) -> String {
        let maanden = Calendar.current.dateComponents([.month], from: Date(), to: tot).month ?? 0
        if tot < Date() { return String(localized: "verlopen") }
        return maanden < 1 ? String(localized: "nog even") : String(localized: "nog \(maanden) mnd")
    }

    private func kleur(_ tot: Date) -> Color {
        tot < Date() ? .secondary : tot.timeIntervalSinceNow < 60 * 86_400 ? Color.accentColor : .secondary
    }
}

// MARK: Terugvinden

/// Leg een plek vast (fiets, auto, tent) en een kompaspijl brengt je terug.
@Observable final class Terugvinder: NSObject, CLLocationManagerDelegate {
    private let lm = CLLocationManager()
    var hier: CLLocation?
    var richting: Double = 0          // waar de bovenkant van je telefoon naartoe wijst

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.headingFilter = 2
    }

    func start() {
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { lm.startUpdatingHeading() }
    }

    func stop() {
        lm.stopUpdatingLocation()
        lm.stopUpdatingHeading()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations plekken: [CLLocation]) { hier = plekken.last }
    func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        richting = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
    }
}

struct TerugvindenView: View {
    @State private var vinder = Terugvinder()
    @AppStorage("terug.naam") private var naam = ""
    @AppStorage("terug.breedte") private var breedte = 0.0
    @AppStorage("terug.lengte") private var lengte = 0.0
    @AppStorage("terug.wanneer") private var wanneer = 0.0
    @AppStorage("haptiek") private var haptiek = true
    @State private var nieuweNaam = ""
    @State private var parkeren = 0
    @Environment(\.modelContext) private var ctx

    private var heeftDoel: Bool { wanneer > 0 }
    private var doel: CLLocation { CLLocation(latitude: breedte, longitude: lengte) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if heeftDoel, let hier = vinder.hier {
                    let afstand = hier.distance(from: doel)
                    let peiling = Kompas.peiling(van: (hier.coordinate.latitude, hier.coordinate.longitude), naar: (breedte, lengte))
                    let dichtbij = afstand < 15
                    VStack(spacing: 18) {
                        Text(naam.isEmpty ? String(localized: "Je plek") : naam).font(.title2.bold())
                        ZStack {
                            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 2).frame(width: 240)
                            Image(systemName: dichtbij ? "checkmark.circle.fill" : "location.north.fill")
                                .font(.system(size: dichtbij ? 90 : 110))
                                .foregroundStyle(Color.accentColor)
                                .rotationEffect(.degrees(dichtbij ? 0 : peiling - vinder.richting))
                                .animation(.interactiveSpring, value: vinder.richting)
                        }
                        .frame(height: 260)
                        .accessibilityHidden(true)
                        Text(dichtbij ? String(localized: "Je bent er!") : afstandTekst(afstand))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("Vastgelegd \(Date(timeIntervalSince1970: wanneer).formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .sensoryFeedback(.success, trigger: dichtbij) { _, nu in haptiek && nu }
                    Button("Plek vergeten", role: .destructive) { wanneer = 0 }.buttonStyle(.bordered)
                } else if heeftDoel {
                    ProgressView("Kompas zoekt je locatie…").padding(.top, 60)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 56)).foregroundStyle(Color.accentColor)
                        Text("Waar laat je iets achter?").font(.title3.bold())
                        Text("Leg de plek van je fiets, auto of tent vast. Straks wijst een pijl je de weg terug.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        TextField("Naam, bijv. Fiets", text: $nieuweNaam)
                            .padding(14)
                            .glas(16)
                        Stepper(parkeren == 0 ? String(localized: "Geen parkeertijd") : String(localized: "Parkeren: \(parkeren) min"),
                                value: $parkeren, in: 0...600, step: 15)
                            .padding(.horizontal, 4)
                        Button {
                            guard let hier = vinder.hier else { return }
                            naam = nieuweNaam
                            breedte = hier.coordinate.latitude
                            lengte = hier.coordinate.longitude
                            wanneer = Date().timeIntervalSince1970
                            if parkeren > 0 {
                                let t = KnivTimer(naam: String(localized: "Parkeren \(nieuweNaam)").trimmingCharacters(in: .whitespaces),
                                                  duur: TimeInterval(parkeren * 60))
                                ctx.insert(t)
                                t.start()
                            }
                            nieuweNaam = ""
                            parkeren = 0
                        } label: { Label("Leg deze plek vast", systemImage: "pin.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(vinder.hier == nil)
                    }
                    .padding(.top, 20)
                }
            }
            .padding()
        }
        .onAppear { vinder.start() }
        .onDisappear { vinder.stop() }
    }

    private func afstandTekst(_ m: Double) -> String {
        m < 1000 ? "\(Int(m.rounded())) m" : "\(Omzetter.mooi(m / 1000)) km"
    }
}

// MARK: QR maken (wifi delen)

struct QRMakenView: View {
    enum Soort: String, CaseIterable { case wifi = "Wifi", tekst = "Tekst of link" }
    @State private var soort: Soort = .wifi
    @AppStorage("qr.netwerk") private var netwerk = ""
    @State private var wachtwoord = ""        // bewust niet bewaard
    @State private var tekst = ""
    @State private var groot = false

    private var inhoud: String? {
        switch soort {
        case .wifi: netwerk.isEmpty ? nil : QRInhoud.wifi(netwerk: netwerk, wachtwoord: wachtwoord)
        case .tekst: tekst.isEmpty ? nil : tekst
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Soort", selection: $soort) {
                    ForEach(Soort.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) }
                }
                .pickerStyle(.segmented)
                VStack(spacing: 12) {
                    if soort == .wifi {
                        TextField("Netwerknaam", text: $netwerk).autocorrectionDisabled().textInputAutocapitalization(.never)
                        SecureField("Wachtwoord", text: $wachtwoord)
                    } else {
                        TextField("Tekst of link", text: $tekst, axis: .vertical).lineLimit(1...5)
                    }
                }
                .padding(16)
                .glas(20)
                if let inhoud, let qr = QR.maak(inhoud) {
                    Button { groot = true } label: {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                            .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .frame(maxWidth: 260)
                    }
                    .accessibilityLabel("QR-code, tik om te vergroten")
                    Text(soort == .wifi ? "Laat je vrienden deze code scannen met hun camera." : "Tik om te vergroten.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .fullScreenCover(isPresented: $groot) {
            ZStack {
                Color.white.ignoresSafeArea()
                if let inhoud, let qr = QR.maak(inhoud) {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().padding(30)
                }
            }
            .onTapGesture { groot = false }
            .onAppear { helderheid = UIScreen.main.brightness; UIScreen.main.brightness = 1 }
            .onDisappear { UIScreen.main.brightness = helderheid }
        }
    }

    @State private var helderheid: CGFloat = 0.5
}
