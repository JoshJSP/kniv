import PhotosUI
import SwiftData
import SwiftUI

struct VastleggenView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Notitie.gewijzigd, order: .reverse) private var notities: [Notitie]
    @Query(sort: \Bakje.volgorde) private var bakjes: [Bakje]
    @StateObject private var spraak = Spraak()
    @AppStorage("haptiek") private var haptiek = true

    @State private var invoer = ""
    @State private var voorSpraak = ""
    @State private var zoek = ""
    @State private var toonCamera = false
    @State private var fotoKeuze: PhotosPickerItem?
    @State private var ontgrendeld: Set<String> = []
    @State private var melding: String?
    @State private var voorstel: (notitie: Notitie, moment: Herinnering.Voorstel)?
    @State private var bewaardTik = 0
    @State private var kiesTik = 0
    @FocusState private var invoerFocus: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                invoerKaart
                if let voorstel { herinneringBalk(voorstel.notitie, voorstel.moment) }
                twijfelSectie
                ForEach(Volgorde.slim(bakjes)) { bakje in
                    let lijst = notities(in: bakje)
                    if !lijst.isEmpty || (bakje.vergrendeld && zoek.isEmpty && heeftNotities(bakje)) {
                        bakjeRij(bakje, lijst)
                    }
                }
                if notities.isEmpty {
                    ContentUnavailableView("Nog niks vastgelegd", systemImage: "tray",
                                           description: Text("Typ, spreek in of maak een foto. Kniv sorteert het voor je."))
                        .padding(.top, 40)
                }
            }
            .padding()
            .animation(.snappy, value: notities.count)
        }
        .background(KnivAchtergrond())
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $zoek, prompt: "Zoek in alles")
        .navigationTitle("Vastleggen")
        .navigationDestination(for: Notitie.self) { NotitieView(notitie: $0) }
        .fullScreenCover(isPresented: $toonCamera) {
            DocumentCamera { beeld in
                toonCamera = false
                if let beeld { Task { await bewaarFoto(beeld) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: fotoKeuze) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let beeld = UIImage(data: data) {
                    await bewaarFoto(beeld)
                }
                fotoKeuze = nil
            }
        }
        .onChange(of: spraak.tekst) { _, t in if spraak.bezig { invoer = voorSpraak + t } }
        .onChange(of: invoer) { oud, nieuw in lijstjeDoorzetten(oud, nieuw) }
        .onChange(of: AppStatus.shared.startInspreken, initial: true) { _, nu in
            guard nu else { return }
            AppStatus.shared.startInspreken = false
            Task { await wisselSpraak() }
        }
        .sensoryFeedback(.success, trigger: bewaardTik) { _, _ in haptiek }
        .sensoryFeedback(.selection, trigger: kiesTik) { _, _ in haptiek }
        .sensoryFeedback(.start, trigger: spraak.bezig) { _, nu in haptiek && nu }
        .alert(melding ?? "", isPresented: Binding(get: { melding != nil }, set: { if !$0 { melding = nil } })) {}
    }

    // MARK: invoer

    private var invoerKaart: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(spraak.bezig ? "Ik luister…" : "Wat wil je kwijt?", text: $invoer, axis: .vertical)
                .lineLimit(1...8)
                .font(.title3)
                .focused($invoerFocus)
            HStack(spacing: 18) {
                Button { Task { await wisselSpraak() } } label: {
                    Image(systemName: spraak.bezig ? "stop.circle.fill" : "mic")
                        .symbolEffect(.pulse, isActive: spraak.bezig)
                        .foregroundStyle(spraak.bezig ? Color.accentColor : Color.primary)
                }
                .accessibilityLabel(spraak.bezig ? "Stop met inspreken" : "Inspreken")
                Button { toonCamera = true } label: { Image(systemName: "camera") }
                    .accessibilityLabel("Foto maken")
                PhotosPicker(selection: $fotoKeuze, matching: .images) { Image(systemName: "photo") }
                    .accessibilityLabel("Foto kiezen")
                Button { beginLijstje() } label: { Image(systemName: "checklist") }
                    .accessibilityLabel("Afvinklijstje")
                Spacer()
                if !invoer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !spraak.bezig {
                    Button { bewaar(invoer, bron: .tekst) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Color.accentColor)
                    }
                    .accessibilityLabel("Bewaar")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .font(.title3)
            .foregroundStyle(.primary)
            .animation(.snappy, value: invoer.isEmpty)
        }
        .padding(18)
        .glas(24)
    }

    private func beginLijstje() {
        if !invoer.isEmpty && !invoer.hasSuffix("\n") { invoer += "\n" }
        invoer += "- "
        invoerFocus = true
    }

    /// Enter na "- melk" zet het volgende streepje klaar; Enter op een leeg streepje stopt het lijstje.
    private func lijstjeDoorzetten(_ oud: String, _ nieuw: String) {
        guard nieuw.count == oud.count + 1, nieuw.hasSuffix("\n") else { return }
        let regels = nieuw.dropLast().components(separatedBy: "\n")
        guard let vorige = regels.last else { return }
        if vorige == "- " {
            invoer = regels.dropLast().joined(separator: "\n") + "\n"
        } else if NotitieParser.lijstItem(vorige) != nil {
            invoer = nieuw + "- "
        }
    }

    private func wisselSpraak() async {
        if spraak.bezig {
            let _ = await spraak.stop()
            bewaar(invoer, bron: .spraak)
        } else {
            voorSpraak = invoer.isEmpty ? "" : invoer + " "
            do { try await spraak.start() } catch {
                melding = "Geef Kniv toegang tot de microfoon en spraakherkenning in Instellingen."
            }
        }
    }

    private func bewaar(_ tekst: String, bron: Bron) {
        guard let n = Vastlegger.bewaar(tekst, bron: bron, in: ctx) else { return }
        invoer = ""
        bewaardTik += 1
        if let moment = Herinnering.vind(in: n.zoekTekst) {
            withAnimation { voorstel = (n, moment) }
        }
        Task { await Vastlegger.sorteer(n, in: ctx) }
    }

    private func bewaarFoto(_ beeld: UIImage) async {
        guard let naam = Fotos.bewaar(beeld) else { melding = "De foto kon niet worden opgeslagen."; return }
        let tekst = await TekstHerkenning.lees(beeld)
        guard let n = Vastlegger.bewaar(invoer, bron: .foto, foto: naam, fotoTekst: tekst, in: ctx) else { return }
        invoer = ""
        bewaardTik += 1
        await Vastlegger.sorteer(n, in: ctx)
    }

    // MARK: herinnering

    private func herinneringBalk(_ n: Notitie, _ moment: Herinnering.Voorstel) -> some View {
        HStack {
            Image(systemName: "bell").foregroundStyle(Color.accentColor)
            Text("Herinneren \(moment.label)?").font(.subheadline)
            Spacer()
            Button("Ja") {
                Task {
                    let gepland = await Herinneraar.plan(n.titel, moment)
                    withAnimation { voorstel = nil }
                    melding = gepland.map { "Staat erin voor \($0.formatted(.dateTime.weekday(.wide).hour().minute()))." }
                        ?? "Kniv mag geen meldingen sturen. Zet het aan in Instellingen."
                }
            }
            .buttonStyle(.borderedProminent)
            Button { withAnimation { voorstel = nil } } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Geen herinnering")
        }
        .padding(14)
        .glas(18)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: twijfel

    @ViewBuilder private var twijfelSectie: some View {
        let open = notities.filter { $0.bakjeNaam == nil }
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Even checken").font(.headline)
                ForEach(open) { n in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(n.titel).lineLimit(2)
                        if n.twijfelOpties.isEmpty {
                            ProgressView().controlSize(.small)
                        } else {
                            HStack {
                                ForEach(n.twijfelOpties, id: \.self) { optie in
                                    Button(optie) { kies(optie, n) }.buttonStyle(.bordered)
                                }
                                Menu("Ander") {
                                    ForEach(bakjes) { b in Button(b.naam) { kies(b.naam, n) } }
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .glas(18)
                }
            }
        }
    }

    private func kies(_ bakje: String, _ n: Notitie) {
        withAnimation(.snappy) { Vastlegger.kies(bakje, voor: n, in: ctx, leer: true) }
        kiesTik += 1
    }

    // MARK: bakjes

    private func heeftNotities(_ b: Bakje) -> Bool { notities.contains { $0.bakjeNaam == b.naam } }

    private func notities(in b: Bakje) -> [Notitie] {
        if b.vergrendeld && !ontgrendeld.contains(b.naam) { return [] }
        return notities.filter { $0.bakjeNaam == b.naam && (zoek.isEmpty || $0.zoekTekst.localizedStandardContains(zoek)) }
    }

    private func bakjeRij(_ b: Bakje, _ lijst: [Notitie]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(b.naam, systemImage: b.symbool).font(.headline)
                if b.vergrendeld { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if !lijst.isEmpty { Text("\(lijst.count)").font(.subheadline).foregroundStyle(.secondary) }
            }
            if b.vergrendeld && !ontgrendeld.contains(b.naam) {
                Button {
                    Task { if await Slot.ontgrendel(b.naam) { _ = withAnimation { ontgrendeld.insert(b.naam) } } }
                } label: {
                    Label("Open met Face ID", systemImage: "faceid").frame(maxWidth: .infinity).padding(14)
                }
                .buttonStyle(.plain)
                .glas(18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(lijst) { n in
                            NavigationLink(value: n) { NotitieKaart(notitie: n) }.buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
    }
}

struct NotitieKaart: View {
    let notitie: Notitie

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let f = notitie.fotoBestand, let mini = Fotos.miniatuur(f) {
                Image(uiImage: mini)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 138, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
            }
            if notitie.isLijst {
                if !notitie.tekst.isEmpty { Text(notitie.titel).font(.subheadline.bold()).lineLimit(1) }
                ForEach(notitie.gesorteerdeItems.prefix(notitie.fotoBestand == nil ? 4 : 1)) { item in
                    Label(item.tekst, systemImage: "circle").font(.caption).lineLimit(1)
                }
            } else {
                Text(notitie.titel).font(.subheadline).lineLimit(notitie.fotoBestand == nil ? 4 : 2)
            }
            Spacer(minLength: 0)
            Text(notitie.gemaakt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 138, height: 150, alignment: .topLeading)
        .padding(12)
        .glas(20)
    }
}

enum Volgorde {
    /// School bovenaan op schooltijd, Boodschappen rond etenstijd, en wat je net gebruikte schuift mee omhoog.
    static func slim(_ bakjes: [Bakje], nu: Date = Date()) -> [Bakje] {
        let kal = Calendar.current
        let uur = kal.component(.hour, from: nu)
        let weekend = kal.isDateInWeekend(nu)
        func score(_ b: Bakje) -> Double {
            var s = max(0, 1.5 - nu.timeIntervalSince(b.laatstGebruikt) / 86_400)
            switch b.naam {
            case "School" where !weekend && (8..<17).contains(uur): s += 2
            case "Boodschappen" where (16..<20).contains(uur) || (weekend && (10..<18).contains(uur)): s += 2
            case "To-do" where (7..<10).contains(uur): s += 1.5
            default: break
            }
            return s
        }
        return bakjes.sorted { score($0) != score($1) ? score($0) > score($1) : $0.volgorde < $1.volgorde }
    }
}

extension Herinnering.Voorstel {
    var label: String {
        let kal = Calendar.current
        let dagTekst = kal.isDateInToday(dag) ? String(localized: "vandaag")
            : kal.isDateInTomorrow(dag) ? String(localized: "morgen")
            : dag.formatted(.dateTime.weekday(.wide).day().month())
        return heeftTijd ? "\(dagTekst) \(dag.formatted(date: .omitted, time: .shortened))" : dagTekst
    }
}
