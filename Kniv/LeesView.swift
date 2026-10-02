import SwiftData
import SwiftUI
import Translation

/// Een leesstukje: grote rustige tekst, voorlezen, tik op een woord.
struct LeesView: View {
    let stuk: Leesstuk
    @Query private var talen: [GekozenTaal]
    @AppStorage("talenLangzaam") private var langzaam = false
    @State private var vermogen: TaalVermogen?
    @State private var ikLees = false
    @State private var getikt: Getikt?
    @State private var oordeel: Taalniveau.Oordeel?

    private struct Getikt: Identifiable {
        let id = UUID()
        let woord: String
        let zin: String
    }

    init(stuk: Leesstuk) {
        self.stuk = stuk
        let code = stuk.taal
        _talen = Query(filter: #Predicate<GekozenTaal> { $0.code == code })
    }

    private var lezer: Voorlezer { Voorlezer.shared }
    private var leest: Bool { ikLees && lezer.bezig }

    var body: some View {
        let woorden = Woorden.knip(stuk.tekst, taal: stuk.taal)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "\(Talen.naam(stuk.taal)) · \(stuk.niveau)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(stuk.titel).font(.largeTitle.bold())
                }
                Text(opgemaakt(woorden))
                    .font(.title3)
                    .lineSpacing(6)
                    .tint(.primary)
                    .environment(\.openURL, OpenURLAction { url in
                        tik(url, woorden)
                        return .handled
                    })
                Text("Tik op een woord voor de betekenis.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if vermogen?.stem == true { StemTip(taal: stuk.taal) }
                if let vermogen {
                    VragenBlok(stuk: stuk, vermogen: vermogen).padding(.top, 12)
                    SchrijfBlok(stuk: stuk, vermogen: vermogen)
                    SpreekBlok(stuk: stuk)
                }
                if let taal = talen.first { oordeelBlok(taal).padding(.top, 12) }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(KnivAchtergrond())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if vermogen?.stem == true { speelBalk }
        }
        .task(id: stuk.taal) { vermogen = await TaalDienst.vermogen(stuk.taal) }
        .onDisappear { lezer.stop() }
        .sheet(item: $getikt) { g in
            WoordKaart(woord: g.woord, zin: g.zin, taal: stuk.taal, woordenlijst: stuk.woorden, vermogen: vermogen ?? .niets)
        }
    }

    /// Elk woord is een link; het woord dat nu klinkt licht op.
    private func opgemaakt(_ woorden: [Woord]) -> AttributedString {
        var a = AttributedString(stuk.tekst)
        let nu = leest ? lezer.gesproken : nil
        for (i, w) in woorden.enumerated() {
            guard let r = Range<AttributedString.Index>(w.bereik, in: a) else { continue }
            a[r].link = URL(string: "kniv-woord://\(i)")
            if let nu, nu.overlaps(w.bereik) {
                a[r][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Color.accentColor.opacity(0.25)
            }
        }
        return a
    }

    private func tik(_ url: URL, _ woorden: [Woord]) {
        guard vermogen != nil, let i = Int(url.absoluteString.replacingOccurrences(of: "kniv-woord://", with: "")),
              woorden.indices.contains(i) else { return }
        lezer.stop()
        ikLees = false
        getikt = Getikt(woord: woorden[i].tekst, zin: Woorden.zin(om: woorden[i].bereik, in: stuk.tekst))
    }

    private func speel() {
        if leest {
            lezer.stop()
            ikLees = false
        } else {
            lezer.lees(stuk.tekst, taal: stuk.taal, snelheid: langzaam ? 0.75 : 1)
            ikLees = true
        }
    }

    private var speelBalk: some View {
        HStack(spacing: 14) {
            Button { speel() } label: {
                Image(systemName: leest ? "stop.fill" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(leest ? Text("Stop") : Text("Voorlezen"))
            Toggle(isOn: $langzaam) { Label("Langzaam", systemImage: "tortoise") }
                .toggleStyle(.button)
                .padding(.trailing, 10)
        }
        .padding(6)
        .glas(40)
        .padding(.bottom, 8)
    }

    private func oordeelBlok(_ taal: GekozenTaal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hoe was dit stukje?").font(.headline)
            if let oordeel {
                uitslag(oordeel).foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack { knoppen(taal) }
                    VStack(alignment: .leading) { knoppen(taal) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glas(22)
    }

    @ViewBuilder private func knoppen(_ taal: GekozenTaal) -> some View {
        knop("Te makkelijk", .teMakkelijk, taal)
        knop("Precies goed", .precies, taal)
        knop("Te moeilijk", .teMoeilijk, taal)
    }

    private func knop(_ titel: LocalizedStringKey, _ o: Taalniveau.Oordeel, _ taal: GekozenTaal) -> some View {
        Button(titel) {
            withAnimation(.snappy) {
                taal.stap = Taalniveau.na(o, stap: taal.stap)
                taal.gewijzigd = Date()
                oordeel = o
            }
        }
        .buttonStyle(.bordered)
    }

    private func uitslag(_ o: Taalniveau.Oordeel) -> Text {
        switch o {
        case .teMakkelijk: return Text("Het volgende stukje wordt iets moeilijker.")
        case .precies: return Text("Top, zo blijft het.")
        case .teMoeilijk: return Text("Het volgende stukje wordt iets makkelijker.")
        }
    }
}

/// Kaartje bij een aangetikt woord: betekenis, uitspraak, lezing en bewaren.
struct WoordKaart: View {
    let woord: String
    let zin: String
    let taal: String
    let woordenlijst: [String: String]
    let vermogen: TaalVermogen
    @Environment(\.modelContext) private var ctx
    @State private var betekenis: String?
    @State private var fout: String?
    @State private var bewaard = false
    @State private var vertalen: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: woord).font(.largeTitle.bold())
                    if let lezing = Woorden.lezing(woord, taal: taal) {
                        Text(verbatim: lezing).font(.title3).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if vermogen.stem {
                    Button { Voorlezer.shared.lees(woord, taal: taal) } label: {
                        Image(systemName: "speaker.wave.2.fill").font(.title2)
                    }
                    .accessibilityLabel("Uitspreken")
                }
            }
            if let betekenis {
                Text(betekenis).font(.title3)
            } else if let fout {
                Text(fout).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            if !zin.isEmpty {
                Text(verbatim: zin).italic().foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                ctx.insert(BewaardWoord(taal: taal, woord: woord, betekenis: betekenis ?? "", zin: zin))
                try? ctx.save()
                bewaard = true
            } label: {
                if bewaard {
                    Label("Bewaard", systemImage: "checkmark").frame(maxWidth: .infinity)
                } else {
                    Label("Bewaar in Mijn woorden", systemImage: "bookmark").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(bewaard || (betekenis == nil && fout == nil))
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .task { await zoekBetekenis() }
        .translationTask(vertalen) { sessie in
            do {
                betekenis = try await sessie.translate(woord).targetText
            } catch {
                fout = String(localized: "Vertalen lukte niet op je iPhone.")
            }
        }
    }

    private func zoekBetekenis() async {
        let sleutel = woord.lowercased()
        switch vermogen.woordBron(inWoordenlijst: woordenlijst[sleutel] != nil) {
        case .woordenlijst:
            betekenis = woordenlijst[sleutel]
        case .toestel:
            vertalen = TranslationSession.Configuration(source: Locale.Language(identifier: taal), target: Locale.Language(identifier: "nl"))
        case .online:
            do {
                betekenis = try await TaalDienst.betekenis(van: woord, zin: zin, taal: taal)
            } catch let f as TaalDienst.Fout {
                fout = f.melding
            } catch {
                fout = TaalDienst.Fout.mislukt.melding
            }
        }
    }
}
