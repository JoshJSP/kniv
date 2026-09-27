import Supabase
import SwiftUI

/// Samen kiezen: een Realtime-kanaal per code. Het rad draait op elke telefoon gelijk (zelfde beginhoek en snelheid,
/// dus dezelfde uitkomst); bij een stemming veegt iedereen op zijn eigen telefoon.
@MainActor @Observable final class SamenKiezen {
    static let shared = SamenKiezen()

    struct Worp: Codable, Equatable {
        var id = UUID()
        var opties: [String]
        var start: Double
        var snelheid: Double
    }

    struct StemStart: Codable, Equatable {
        var id = UUID()
        var opties: [String]
    }

    struct Stem: Codable {
        var naam: String
        var ja: [String]
    }

    private struct Aanwezig: Codable { let naam: String }
    private struct Omslag<T: Decodable>: Decodable { let payload: T }

    var code: String?
    var deelnemers: [String] = []
    var worp: Worp?
    var stemming: StemStart?
    var stemmen: [String: Set<String>] = [:]

    private var kanaal: RealtimeChannelV2?
    private var taken: [Task<Void, Never>] = []

    var mijnNaam: String {
        let volledig = Sync.shared.naam
        return volledig.isEmpty ? String(localized: "Ik") : String(volledig.split(separator: " ").first ?? "Ik")
    }

    static func nieuweCode() -> String { String((0..<4).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ".randomElement()! }) }
    static func link(_ code: String) -> URL { URL(string: "https://kniv.vercel.app/k/\(code)")! }

    func doeMee(_ code: String) async {
        await stop()
        let schoon = code.uppercased().filter(\.isLetter)
        guard schoon.count == 4 else { return }
        self.code = schoon
        let k = KnivCloud.client.channel("kiezen-\(schoon)")
        kanaal = k
        let worpen = k.broadcastStream(event: "rad")
        let starts = k.broadcastStream(event: "stemming")
        let stemStroom = k.broadcastStream(event: "stem")
        let aanwezigheid = k.presenceChange()
        taken = [
            Task { for await m in worpen { if let w: Worp = Self.lees(m) { worp = w } } },
            Task {
                for await m in starts {
                    if let s: StemStart = Self.lees(m) { stemming = s; stemmen = [:] }
                }
            },
            Task { for await m in stemStroom { if let s: Stem = Self.lees(m) { stemmen[s.naam] = Set(s.ja) } } },
            Task {
                for await p in aanwezigheid {
                    let erbij = (try? p.decodeJoins(as: Aanwezig.self))?.map(\.naam) ?? []
                    let weg = Set((try? p.decodeLeaves(as: Aanwezig.self))?.map(\.naam) ?? [])
                    deelnemers = Array(Set(deelnemers + erbij).subtracting(weg)).sorted()
                }
            },
        ]
        await k.subscribe()
        try? await k.track(Aanwezig(naam: mijnNaam))
    }

    func stop() async {
        taken.forEach { $0.cancel() }
        taken = []
        if let kanaal { await kanaal.unsubscribe() }
        kanaal = nil
        code = nil
        deelnemers = []
        stemming = nil
        stemmen = [:]
    }

    func draai(opties: [String], start: Double, snelheid: Double) {
        let w = Worp(opties: opties, start: start, snelheid: snelheid)
        worp = w
        Task { try? await kanaal?.broadcast(event: "rad", message: w) }
    }

    func startStemming(_ opties: [String]) {
        let s = StemStart(opties: opties)
        stemming = s
        stemmen = [:]
        Task { try? await kanaal?.broadcast(event: "stemming", message: s) }
    }

    func stem(_ ja: Set<String>) {
        stemmen[mijnNaam] = ja
        Task { try? await kanaal?.broadcast(event: "stem", message: Stem(naam: mijnNaam, ja: Array(ja))) }
    }

    /// Klaar als iedereen die in het kanaal zit gestemd heeft.
    var iedereenGestemd: Bool {
        let wie = Set(deelnemers).union([mijnNaam])
        return !stemmen.isEmpty && wie.isSubset(of: Set(stemmen.keys))
    }

    private static func lees<T: Decodable>(_ bericht: JSONObject) -> T? {
        guard let data = try? JSONEncoder().encode(bericht) else { return nil }
        if let o = try? JSONDecoder().decode(Omslag<T>.self, from: data) { return o.payload }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Balk bovenin Kiezen: samen starten, meedoen of zien wie er is.
struct SamenBalk: View {
    @State private var samen = SamenKiezen.shared
    @State private var toonMeedoen = false
    @State private var invoer = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill").foregroundStyle(Color.accentColor)
            if let code = samen.code {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Samen · \(code)").font(.subheadline.weight(.semibold))
                    Text(samen.deelnemers.isEmpty ? String(localized: "Wachten op anderen…") : samen.deelnemers.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                ShareLink(item: SamenKiezen.link(code), message: Text("Kies mee in Kniv")) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Nodig uit")
                Button { Task { await samen.stop() } } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Stop samen kiezen")
            } else {
                Text("Kies samen met vrienden").font(.subheadline)
                Spacer()
                Button("Start") { Task { await samen.doeMee(SamenKiezen.nieuweCode()) } }.buttonStyle(.bordered)
                Button("Doe mee") { toonMeedoen = true }.buttonStyle(.bordered)
            }
        }
        .padding(12)
        .glas(18)
        .padding(.horizontal)
        .alert("Code van je vriend", isPresented: $toonMeedoen) {
            TextField("ABCD", text: $invoer).textInputAutocapitalization(.characters)
            Button("Doe mee") { Task { await samen.doeMee(invoer); invoer = "" } }
            Button("Annuleer", role: .cancel) {}
        }
    }
}

/// Stemmen met iedereen in het kanaal, ieder op zijn eigen telefoon.
struct SamenStemView: View {
    @Binding var opties: [String]
    @State private var samen = SamenKiezen.shared
    @State private var index = 0
    @State private var ja: Set<String> = []
    @State private var sleep: CGSize = .zero

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let stemming = samen.stemming {
                    if samen.iedereenGestemd {
                        uitslag(stemming.opties)
                    } else if samen.stemmen[samen.mijnNaam] != nil || index >= stemming.opties.count {
                        ProgressView()
                        Text("Wachten tot iedereen gestemd heeft (\(samen.stemmen.count)/\(Set(samen.deelnemers).union([samen.mijnNaam]).count))")
                            .foregroundStyle(.secondary)
                    } else {
                        kaart(stemming.opties[index], opties: stemming.opties)
                        Text("Rechts = ja, links = nee").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    OptieEditor(opties: $opties)
                    Button { index = 0; ja = []; samen.startStemming(opties) } label: {
                        Label("Start stemming voor iedereen", systemImage: "hand.thumbsup").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(opties.count < 2)
                }
            }
            .padding()
        }
        .onChange(of: samen.stemming) { index = 0; ja = [] }
    }

    private func kaart(_ optie: String, opties: [String]) -> some View {
        Text(optie)
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .glas(30)
            .offset(x: sleep.width)
            .rotationEffect(.degrees(sleep.width / 18))
            .gesture(DragGesture()
                .onChanged { sleep = $0.translation }
                .onEnded { v in
                    guard abs(v.translation.width) > 110 else { withAnimation(.spring) { sleep = .zero }; return }
                    if v.translation.width > 0 { ja.insert(optie) }
                    withAnimation(.snappy) { sleep = .zero; index += 1 }
                    if index >= opties.count { samen.stem(ja) }
                })
            .id(index)
            .accessibilityElement()
            .accessibilityLabel(optie)
            .accessibilityAction(named: "Ja") { ja.insert(optie); index += 1; if index >= opties.count { samen.stem(ja) } }
            .accessibilityAction(named: "Nee") { index += 1; if index >= opties.count { samen.stem(ja) } }
    }

    private func uitslag(_ opties: [String]) -> some View {
        let winnaars = Stemming.winnaars(samen.stemmen, opties: opties)
        return VStack(spacing: 12) {
            Text("En de winnaar is…").foregroundStyle(.secondary)
            Text(winnaars.isEmpty ? "Niemand wilde iets 🙃" : winnaars.joined(separator: " & "))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .multilineTextAlignment(.center)
            ForEach(opties.sorted { Stemming.ja($0, samen.stemmen) > Stemming.ja($1, samen.stemmen) }, id: \.self) { o in
                HStack { Text(o); Spacer(); Text("\(Stemming.ja(o, samen.stemmen)) × ja").foregroundStyle(.secondary) }
            }
            Button("Nieuwe stemming") { samen.stemming = nil }.buttonStyle(.bordered)
        }
        .padding(20)
        .glas(26)
    }
}
