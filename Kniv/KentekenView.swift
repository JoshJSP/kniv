import SwiftData
import SwiftUI

/// Kenteken opzoeken bij de RDW (open data, geen account): wat voor auto, APK, verzekerd, teller logisch, terugroepactie.
struct KentekenView: View {
    struct Voertuig: Decodable {
        var merk: String?
        var handelsbenaming: String?
        var voertuigsoort: String?
        var eerste_kleur: String?
        var vervaldatum_apk: String?
        var datum_eerste_toelating: String?
        var wam_verzekerd: String?
        var tellerstandoordeel: String?
        var openstaande_terugroepactie_indicator: String?
        var catalogusprijs: String?
        var aantal_zitplaatsen: String?
        var massa_rijklaar: String?
    }

    struct Brandstof: Decodable {
        var brandstof_omschrijving: String?
        var brandstofverbruik_gecombineerd: String?
    }

    @Environment(\.modelContext) private var ctx
    @AppStorage("kenteken.laatste") private var invoer = ""
    @State private var voertuig: Voertuig?
    @State private var brandstof: Brandstof?
    @State private var gezocht: String?
    @State private var bezig = false
    @State private var fout: LocalizedStringKey?
    @State private var toonCamera = false
    @State private var herinnerd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                plaat
                HStack(spacing: 12) {
                    Button { Task { await zoek() } } label: {
                        Label("Opzoeken", systemImage: "magnifyingglass").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(Kenteken.normaal(invoer) == nil || bezig)
                    Button { toonCamera = true } label: { Image(systemName: "camera").padding(.vertical, 6) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Kenteken fotograferen")
                }
                if bezig { ProgressView() }
                if let fout { Text(fout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if let v = voertuig, let k = gezocht { kaart(v, k) }
                Text("Gegevens van de RDW (open data).").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .fullScreenCover(isPresented: $toonCamera) {
            DocumentCamera { beeld in
                toonCamera = false
                guard let beeld else { return }
                Task {
                    if let k = Kenteken.vind(in: await TekstHerkenning.lees(beeld)) {
                        invoer = Kenteken.mooi(k)
                        await zoek()
                    } else {
                        fout = "Geen kenteken gevonden op de foto."
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    /// Een echte gele Nederlandse plaat, met de blauwe NL-strook.
    private var plaat: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Image(systemName: "star.circle").font(.caption2)
                Text(verbatim: "NL").font(.headline.bold())
            }
            .foregroundStyle(.white)
            .frame(width: 40)
            .frame(maxHeight: .infinity)
            .background(Color(red: 0, green: 0.2, blue: 0.6))
            TextField(text: $invoer, prompt: Text(verbatim: "GZ-738-T").foregroundStyle(.black.opacity(0.3))) { Text("Kenteken") }
                .font(.system(size: 38, weight: .heavy, design: .monospaced))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await zoek() } }
        }
        .frame(height: 72)
        .background(Color(red: 1, green: 0.8, blue: 0))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.black, lineWidth: 3))
        .padding(.horizontal, 12)
    }

    private func kaart(_ v: Voertuig, _ k: String) -> some View {
        let apk = Kenteken.datum(v.vervaldatum_apk)
        let bouwjaar = Kenteken.datum(v.datum_eerste_toelating).map { Calendar.current.component(.year, from: $0) }
        let apkBijna = apk.map { $0.timeIntervalSinceNow < 30 * 86_400 } ?? false
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: [v.merk, v.handelsbenaming?.replacingOccurrences(of: v.merk ?? "", with: "").trimmingCharacters(in: .whitespaces)]
                    .compactMap { $0?.capitalized }.filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.title2.bold())
                Text(verbatim: [v.voertuigsoort, v.eerste_kleur?.capitalized, bouwjaar.map(String.init), brandstof?.brandstof_omschrijving]
                    .compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            Divider()
            if let apk {
                regel(apkBijna ? "exclamationmark.triangle.fill" : "checkmark.seal.fill", apkBijna ? .orange : .green,
                      Text("APK tot \(apk.formatted(date: .long, time: .omitted))"))
            }
            if let wam = v.wam_verzekerd {
                regel(wam == "Ja" ? "checkmark.shield.fill" : "xmark.shield.fill", wam == "Ja" ? .green : .red,
                      wam == "Ja" ? Text("Verzekerd") : Text("Niet verzekerd"))
            }
            if let teller = v.tellerstandoordeel, teller != "Geen oordeel" {
                regel(teller == "Logisch" ? "gauge.with.dots.needle.33percent" : "exclamationmark.triangle.fill", teller == "Logisch" ? .green : .orange,
                      Text("Kilometerstand: \(teller.lowercased())"))
            }
            if v.openstaande_terugroepactie_indicator == "Ja" {
                regel("wrench.and.screwdriver.fill", .orange, Text("Er loopt een terugroepactie. Vraag de dealer ernaar."))
            }
            if let l = brandstof?.brandstofverbruik_gecombineerd.flatMap(Double.init), l > 0 {
                regel("fuelpump.fill", .secondary, Text("Verbruik \(Omzetter.mooi(l)) l/100 km (1 op \(Omzetter.mooi(100 / l)))"))
            }
            if let prijs = v.catalogusprijs.flatMap(Double.init) {
                regel("eurosign.circle", .secondary, Text("Nieuwprijs \(Omzetter.euro(prijs))"))
            }
            if let apk, apk > Date() {
                Button {
                    guard let n = Vastlegger.bewaar("APK \(Kenteken.mooi(k)) (\(v.merk?.capitalized ?? "")) verloopt \(apk.formatted(date: .numeric, time: .omitted))",
                                                    bron: .tekst, in: ctx) else { return }
                    // zonder sorteren bleef hij eeuwig op "Even checken" draaien
                    Task { await Vastlegger.sorteer(n, in: ctx) }
                    let maandEerder = Calendar.current.date(byAdding: .day, value: -30, to: apk) ?? apk
                    Task { _ = await Herinneraar.plan(n.titel, Herinnering.Voorstel(dag: max(maandEerder, Date().addingTimeInterval(3600)), heeftTijd: false), id: n.uid) }
                    herinnerd = true
                } label: {
                    Label(herinnerd ? "Staat in Kniv" : "Herinner me een maand voor de APK", systemImage: herinnerd ? "checkmark" : "bell")
                }
                .disabled(herinnerd)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glas(22)
    }

    private func regel(_ icoon: String, _ kleur: Color, _ tekst: Text) -> some View {
        Label { tekst } icon: { Image(systemName: icoon).foregroundStyle(kleur) }
    }

    private func zoek() async {
        guard let k = Kenteken.normaal(invoer) else { return }
        bezig = true
        fout = nil
        herinnerd = false
        defer { bezig = false }
        func haal<T: Decodable>(_ set: String) async throws -> [T] {
            let url = URL(string: "https://opendata.rdw.nl/resource/\(set).json?kenteken=\(k)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([T].self, from: data)
        }
        do {
            async let v: [Voertuig] = haal("m9d7-ebf2")
            async let b: [Brandstof] = haal("8ys7-d773")
            let gevonden = try await v
            guard let eerste = gevonden.first else {
                voertuig = nil
                fout = "Dit kenteken kent de RDW niet."
                return
            }
            voertuig = eerste
            brandstof = (try? await b)?.first
            gezocht = k
            invoer = Kenteken.mooi(k)
        } catch {
            fout = "De RDW is even niet bereikbaar."
        }
    }
}
