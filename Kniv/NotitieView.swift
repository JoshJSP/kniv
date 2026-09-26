import SwiftData
import SwiftUI

struct NotitieView: View {
    @Bindable var notitie: Notitie
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bakje.volgorde) private var bakjes: [Bakje]
    @AppStorage("haptiek") private var haptiek = true

    @State private var doorgestreept: Set<PersistentIdentifier> = []
    @State private var nieuwItem = ""
    @State private var lijstAan = false
    @State private var herinnering: String?
    @State private var toonFoto = false
    @State private var timerGestart = false

    var body: some View {
        List {
            if let f = notitie.fotoBestand, let beeld = Fotos.miniatuur(f) {
                Section {
                    Button { toonFoto = true } label: {
                        Image(uiImage: beeld).resizable().scaledToFit().frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel("Foto, tik om te vergroten")
                }
                .listRowInsets(EdgeInsets())
            }

            Section {
                TextField("Notitie", text: $notitie.tekst, axis: .vertical)
                    .lineLimit(1...20)
                    .onChange(of: notitie.tekst) { notitie.gewijzigd = Date() }
            }

            if notitie.isLijst || lijstAan {
                Section("Lijstje") {
                    ForEach(notitie.gesorteerdeItems) { item in
                        let weg = doorgestreept.contains(item.persistentModelID)
                        Button { vink(item) } label: {
                            HStack {
                                Image(systemName: weg ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(weg ? Color.accentColor : Color.secondary)
                                Text(item.tekst)
                                    .strikethrough(weg)
                                    .foregroundStyle(weg ? .secondary : .primary)
                            }
                        }
                        .accessibilityValue(weg ? "Afgevinkt" : "")
                        .accessibilityHint(weg ? "Tik om ongedaan te maken" : "Tik om af te vinken")
                    }
                    TextField("Nieuw item", text: $nieuwItem)
                        .onSubmit(voegToe)
                        .submitLabel(.next)
                }
            } else {
                Button { lijstAan = true } label: { Label("Afvinklijstje toevoegen", systemImage: "checklist") }
            }

            if !notitie.fotoTekst.isEmpty {
                Section("Tekst uit de foto") {
                    Text(notitie.fotoTekst).textSelection(.enabled)
                }
            }

            if let voorstel = TimerParser.vind(in: notitie.tekst) {
                Section {
                    Button {
                        let t = KnivTimer(naam: voorstel.naam, duur: TimeInterval(voorstel.seconden))
                        ctx.insert(t)
                        t.start()
                        timerGestart = true
                    } label: {
                        Label(timerGestart ? "Timer loopt" : "Timer: \(voorstel.naam), \(TimerParser.klok(TimeInterval(voorstel.seconden)))",
                              systemImage: "timer")
                    }
                    .disabled(timerGestart)
                }
            }

            if let moment = Herinnering.vind(in: notitie.zoekTekst) {
                Section {
                    Button {
                        Task {
                            let gepland = await Herinneraar.plan(notitie.titel, moment)
                            herinnering = gepland.map { "Herinnering: \($0.formatted(.dateTime.weekday(.wide).hour().minute()))" }
                                ?? "Meldingen staan uit voor Kniv"
                        }
                    } label: {
                        Label(herinnering ?? "Herinner me \(moment.label)", systemImage: "bell")
                    }
                    .disabled(herinnering != nil)
                }
            }

            Section {
                Picker("Bakje", selection: Binding(get: { notitie.bakjeNaam }, set: { nieuw in
                    if let nieuw { Vastlegger.kies(nieuw, voor: notitie, in: ctx, leer: true) }
                })) {
                    if notitie.bakjeNaam == nil { Text("Nog niet gesorteerd").tag(String?.none) }
                    ForEach(bakjes) { Label($0.naam, systemImage: $0.symbool).tag(Optional($0.naam)) }
                }
                ShareLink(item: deelTekst) { Label("Delen", systemImage: "square.and.arrow.up") }
            }

            Section {
                Button("Verwijder notitie", role: .destructive) {
                    let n = notitie
                    dismiss()
                    // Pas weghalen als het scherm weg is, anders leest het een verwijderde notitie.
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        Vastlegger.verwijder(n, in: ctx)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KnivAchtergrond())
        .navigationTitle(notitie.bakjeNaam ?? "Notitie")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: doorgestreept.count) { _, _ in haptiek }
        .fullScreenCover(isPresented: $toonFoto) { FotoView(bestand: notitie.fotoBestand) }
    }

    private var deelTekst: String {
        ([notitie.tekst] + notitie.gesorteerdeItems.map { "- \($0.tekst)" } + [notitie.fotoTekst])
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func voegToe() {
        let t = nieuwItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        notitie.items.append(LijstItem(tekst: t, volgorde: (notitie.items.map(\.volgorde).max() ?? -1) + 1))
        notitie.gewijzigd = Date()
        nieuwItem = ""
    }

    /// Doorstrepen, twee tellen wachten, weg. Nog een tik in die twee tellen maakt het ongedaan.
    private func vink(_ item: LijstItem) {
        let id = item.persistentModelID
        if doorgestreept.remove(id) != nil { return }
        withAnimation(.snappy) { _ = doorgestreept.insert(id) }
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard doorgestreept.contains(id) else { return }
            withAnimation(.snappy) {
                doorgestreept.remove(id)
                ctx.delete(item)
                notitie.gewijzigd = Date()
            }
        }
    }
}

struct FotoView: View {
    let bestand: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let bestand, let beeld = UIImage(contentsOfFile: Fotos.url(bestand).path) {
                Image(uiImage: beeld).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.largeTitle).symbolRenderingMode(.hierarchical).foregroundStyle(.white)
            }
            .accessibilityLabel("Sluiten")
            .padding()
        }
    }
}

struct InstellingenView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Bakje.volgorde) private var bakjes: [Bakje]
    @AppStorage("haptiek") private var haptiek = true
    @State private var nieuwBakje = ""

    var body: some View {
        Form {
            Section {
                ForEach(bakjes) { BakjeRij(bakje: $0) }
                    .onDelete(perform: verwijder)
                HStack {
                    TextField("Nieuw bakje", text: $nieuwBakje).onSubmit(voegToe)
                    Button("Voeg toe", action: voegToe).disabled(nieuwBakje.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Mijn bakjes")
            } footer: {
                Text("Met het slotje open je een bakje alleen met Face ID. Eigen bakjes herkent Kniv zodra je hun naam gebruikt, en leert hij van jouw keuzes.")
            }

            Section {
                Toggle("Trillingen", isOn: $haptiek)
            }

            Section {
                LabeledContent("Versie", value: VersieInfo.huidig.map { "\($0.mesnaam) · \($0.versie)" } ?? "?")
            }
        }
        .navigationTitle("Instellingen")
    }

    private func voegToe() {
        let naam = nieuwBakje.trimmingCharacters(in: .whitespaces)
        guard !naam.isEmpty, !bakjes.contains(where: { $0.naam.caseInsensitiveCompare(naam) == .orderedSame }) else { return }
        ctx.insert(Bakje(naam: naam, symbool: "tray", volgorde: (bakjes.map(\.volgorde).max() ?? 0) + 1))
        nieuwBakje = ""
    }

    private func verwijder(_ plekken: IndexSet) {
        for i in plekken where !bakjes[i].vast {
            let naam: String? = bakjes[i].naam
            let wees = (try? ctx.fetch(FetchDescriptor<Notitie>(predicate: #Predicate { $0.bakjeNaam == naam }))) ?? []
            ctx.delete(bakjes[i])
            for n in wees {
                n.bakjeNaam = nil
                Task { await Vastlegger.sorteer(n, in: ctx) }
            }
        }
    }
}

struct BakjeRij: View {
    @Bindable var bakje: Bakje
    @Environment(\.modelContext) private var ctx
    @State private var naam = ""

    var body: some View {
        HStack {
            Image(systemName: bakje.symbool).foregroundStyle(Color.accentColor).frame(width: 26)
            TextField("Naam", text: $naam)
                .onSubmit(hernoem)
                .disabled(bakje.vast)
            Toggle(isOn: $bakje.vergrendeld) { Image(systemName: bakje.vergrendeld ? "lock.fill" : "lock.open") }
                .toggleStyle(.button)
                .accessibilityLabel(bakje.vergrendeld ? "Vergrendeld met Face ID" : "Niet vergrendeld")
        }
        .onAppear { naam = bakje.naam }
    }

    private func hernoem() {
        let nieuw = naam.trimmingCharacters(in: .whitespaces)
        guard !nieuw.isEmpty, nieuw != bakje.naam else { naam = bakje.naam; return }
        let oud: String? = bakje.naam
        let notities = (try? ctx.fetch(FetchDescriptor<Notitie>(predicate: #Predicate { $0.bakjeNaam == oud }))) ?? []
        notities.forEach { $0.bakjeNaam = nieuw }
        bakje.naam = nieuw
    }
}
