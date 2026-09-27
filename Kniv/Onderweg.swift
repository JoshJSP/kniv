import AVFoundation
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

// MARK: Achtergrondgeluid: ruis om bij te focussen of in slaap te vallen

@Observable final class Ruis {
    static let shared = Ruis()
    enum Kleur: String, CaseIterable { case bruin = "Bruin", roze = "Roze", wit = "Wit" }

    private(set) var aan = false
    private(set) var stopOm: Date?
    var kleur: Kleur = .bruin
    var volume: Float = 0.5
    private var engine: AVAudioEngine?
    private var wekker: Task<Void, Never>?

    func start(minuten: Int?) {
        stop()
        let sessie = AVAudioSession.sharedInstance()
        try? sessie.setCategory(.playback, options: [.mixWithOthers])
        try? sessie.setActive(true)
        let e = AVAudioEngine()
        let rate = e.outputNode.outputFormat(forBus: 0).sampleRate
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44_100, channels: 1) else { return }
        let soort = kleur
        var bruin: Float = 0
        var p = [Float](repeating: 0, count: 7)      // Paul Kellet's roze-ruisfilter
        let bron = AVAudioSourceNode { _, _, frames, lijst -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(lijst)
            for f in 0..<Int(frames) {
                let wit = Float.random(in: -1...1)
                var s: Float
                switch soort {
                case .wit:
                    s = wit * 0.25
                case .bruin:
                    bruin = (bruin + 0.02 * wit) / 1.02
                    s = bruin * 3.5 * 0.5
                case .roze:
                    p[0] = 0.99886 * p[0] + wit * 0.0555179
                    p[1] = 0.99332 * p[1] + wit * 0.0750759
                    p[2] = 0.96900 * p[2] + wit * 0.1538520
                    p[3] = 0.86650 * p[3] + wit * 0.3104856
                    p[4] = 0.55000 * p[4] + wit * 0.5329522
                    p[5] = -0.7616 * p[5] - wit * 0.0168980
                    s = (p[0] + p[1] + p[2] + p[3] + p[4] + p[5] + p[6] + wit * 0.5362) * 0.05
                    p[6] = wit * 0.115926
                }
                for b in buffers { b.mData?.assumingMemoryBound(to: Float.self)[f] = s }
            }
            return noErr
        }
        e.attach(bron)
        e.connect(bron, to: e.mainMixerNode, format: mono)
        e.mainMixerNode.outputVolume = volume
        guard (try? e.start()) != nil else { return }
        engine = e
        aan = true
        if let minuten {
            stopOm = Date().addingTimeInterval(Double(minuten) * 60)
            wekker = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(minuten * 60))
                if !Task.isCancelled { self?.stop() }
            }
        }
    }

    func zetVolume() { engine?.mainMixerNode.outputVolume = volume }

    func stop() {
        wekker?.cancel()
        wekker = nil
        engine?.stop()
        engine = nil
        aan = false
        stopOm = nil
    }
}

struct RuisView: View {
    @State private var ruis = Ruis.shared
    @State private var minuten: Int? = 30
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                Picker("Soort", selection: $ruis.kleur) {
                    ForEach(Ruis.Kleur.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) }
                }
                .pickerStyle(.segmented)
                .onChange(of: ruis.kleur) { if ruis.aan { ruis.start(minuten: minuten) } }
                Text(uitleg).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

                Button {
                    ruis.aan ? ruis.stop() : ruis.start(minuten: minuten)
                } label: {
                    Image(systemName: ruis.aan ? "pause.fill" : "play.fill")
                        .font(.system(size: 50))
                        .frame(width: 150, height: 150)
                        .foregroundStyle(.white)
                        .background(Color.accentColor.gradient, in: Circle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: ruis.aan)
                .accessibilityLabel(ruis.aan ? "Stop" : "Start")

                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $ruis.volume, in: 0...1)
                        .onChange(of: ruis.volume) { ruis.zetVolume() }
                    Image(systemName: "speaker.wave.3.fill")
                }
                .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    Text("Stopt vanzelf na").font(.subheadline)
                    HStack {
                        ForEach([15, 30, 60], id: \.self) { m in
                            keuze(Text("\(m) min"), gekozen: minuten == m) { minuten = m }
                        }
                        keuze(Text("Nooit"), gekozen: minuten == nil) { minuten = nil }
                    }
                    if let om = ruis.stopOm {
                        Text("Stopt om \(om.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(24)
            .background(KnivAchtergrond())
            .navigationTitle("Achtergrondgeluid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Klaar") { dismiss() } }
        }
    }

    private var uitleg: LocalizedStringKey {
        switch ruis.kleur {
        case .bruin: "Diep en zacht, als een waterval. Fijn om te focussen."
        case .roze: "Als regen op het dak. Fijn om in slaap te vallen."
        case .wit: "Als een ventilator. Dekt geluiden van buiten af."
        }
    }

    private func keuze(_ tekst: Text, gekozen: Bool, actie: @escaping () -> Void) -> some View {
        Button(action: actie) {
            tekst.font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(gekozen ? Color.white : Color.primary)
                .background(gekozen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Onderweg: "Ik ben er rond 14:32", berekend en klaar om te sturen

struct OnderwegView: View {
    enum Vervoer: String, CaseIterable { case lopen = "Lopen", fiets = "Fiets", ov = "OV", auto = "Auto" }

    @Query(sort: \Plek.naam) private var plekken: [Plek]
    @AppStorage("onderweg.vervoer") private var vervoer: Vervoer = .fiets
    @State private var zoek = ""
    @State private var doelNaam: String?
    @State private var aankomst: Date?
    @State private var bezig = false
    @State private var fout: String?
    @State private var lm = CLLocationManager()
    @Environment(\.dismiss) private var dismiss

    private var bericht: String? {
        aankomst.map { String(localized: "Ik ben er rond \($0.formatted(date: .omitted, time: .shortened)).") }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Vervoer", selection: $vervoer) {
                        ForEach(Vervoer.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                if let bericht, let aankomst, let doelNaam {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: bericht).font(.title2.weight(.semibold))
                            Text("Naar \(doelNaam), over \(max(Int(aankomst.timeIntervalSinceNow / 60), 1)) min").font(.subheadline).foregroundStyle(.secondary)
                        }
                        ShareLink(item: bericht) { Label("Stuur dit", systemImage: "paperplane.fill") }
                    }
                }

                Section("Waar ga je heen?") {
                    ForEach(plekken) { p in
                        Button {
                            Task { await bereken(p.naam, MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: p.breedte, longitude: p.lengte)))) }
                        } label: {
                            Label(p.naam, systemImage: p.soort == "thuis" ? "house.fill" : p.soort == "school" ? "graduationcap.fill" : "mappin")
                        }
                    }
                    TextField("Zoek een adres of plek", text: $zoek)
                        .submitLabel(.search)
                        .onSubmit { Task { await zoekAdres() } }
                }

                if bezig { ProgressView().frame(maxWidth: .infinity) }
                if let fout { Text(verbatim: fout).foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden)
            .background(KnivAchtergrond())
            .navigationTitle("Ik ben er om…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Klaar") { dismiss() } }
            .onAppear { if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization() } }
            .onChange(of: vervoer) { aankomst = nil }
        }
    }

    private func zoekAdres() async {
        let vraag = MKLocalSearch.Request()
        vraag.naturalLanguageQuery = zoek
        guard let item = try? await MKLocalSearch(request: vraag).start().mapItems.first else {
            fout = String(localized: "Niets gevonden. Probeer het met een plaatsnaam erbij.")
            return
        }
        await bereken(item.name ?? zoek, item)
    }

    private func bereken(_ naam: String, _ doel: MKMapItem) async {
        bezig = true
        fout = nil
        defer { bezig = false }
        let vraag = MKDirections.Request()
        vraag.source = .forCurrentLocation()
        vraag.destination = doel
        vraag.transportType = switch vervoer {
        case .lopen, .fiets: .walking
        case .ov: .transit
        case .auto: .automobile
        }
        do {
            let eta = try await MKDirections(request: vraag).calculateETA()
            // ponytail: Kaarten kent geen fiets-ETA; 16 km/u over de looproute ligt dicht bij de werkelijkheid in Nederland.
            let reistijd = vervoer == .fiets ? eta.distance / (16 / 3.6) : eta.expectedTravelTime
            aankomst = Date().addingTimeInterval(reistijd)
            doelNaam = naam
        } catch {
            aankomst = nil
            fout = vervoer == .ov ? String(localized: "Geen OV-tijden voor deze route. Probeer lopen of fiets.")
                : String(localized: "Kon de route niet berekenen. Staat locatie aan?")
        }
    }
}
