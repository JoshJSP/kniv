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
    @State private var plekBewaard: Bool?
    @State private var deelToken: String?

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
                if notitie.bakjeNaam == "Boodschappen" && notitie.items.count > 2 {
                    // In de volgorde van een rondje door de supermarkt.
                    ForEach(Gangpad.route(notitie.gesorteerdeItems) { $0.tekst }, id: \.0) { groep in
                        Section(LocalizedStringKey(groep.0.naam)) { ForEach(groep.1) { itemRij($0) } }
                    }
                    Section { nieuwItemVeld }
                } else {
                    Section("Lijstje") {
                        ForEach(notitie.gesorteerdeItems) { itemRij($0) }
                        nieuwItemVeld
                    }
                }
            } else {
                Button { lijstAan = true } label: { Label("Afvinklijstje toevoegen", systemImage: "checklist") }
            }

            if !notitie.fotoTekst.isEmpty {
                Section("Tekst uit de foto") {
                    Text(notitie.fotoTekst).textSelection(.enabled)
                }
            }

            if notitie.items.count >= 2 {
                Section("Kies uit dit lijstje") {
                    HStack {
                        ForEach([("Rad", "circle.dashed"), ("Teams", "person.2"), ("Stemmen", "hand.thumbsup")], id: \.0) { paar in
                            Button { kies(paar.0) } label: { Label(LocalizedStringKey(paar.0), systemImage: paar.1) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if BonParser.lijktBon(notitie.fotoTekst) || notitie.garantieTot != nil {
                GarantieSectie(notitie: notitie)
            }

            if BonParser.lijktBon(notitie.fotoTekst) {
                Section {
                    Button {
                        AppStatus.shared.bonTekst = notitie.fotoTekst
                        AppStatus.shared.openSplitten = true
                    } label: { Label("Splitten met deze bon", systemImage: "divide") }
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
                Button {
                    Task { plekBewaard = await PlekWachter.shared.bewaarHier(naam: notitie.titel, soort: "eigen", bericht: notitie.titel) }
                } label: {
                    Label(plekBewaard == true ? "Kniv herinnert je hier" : plekBewaard == false ? "Locatie niet gevonden" : "Herinner me op deze plek",
                          systemImage: "mappin.and.ellipse")
                }
                .disabled(plekBewaard == true)
            }

            Section {
                Picker("Waar", selection: Binding(get: { notitie.deling }, set: zetDeling)) {
                    Label("Alleen deze telefoon", systemImage: "iphone").tag("prive")
                    Label("Ook op mijn laptop", systemImage: "laptopcomputer.and.iphone").tag("laptop")
                    Label("Gedeeld", systemImage: "person.2").tag("gedeeld")
                }
                if notitie.deling == "gedeeld" {
                    if let deelToken {
                        ShareLink(item: Sync.uitnodiging(deelToken), subject: Text(notitie.titel),
                                  message: Text("Doe mee met mijn lijstje in Kniv")) {
                            Label("Nodig iemand uit", systemImage: "person.badge.plus")
                        }
                        ShareLink(item: Sync.bekijklink(deelToken), subject: Text(notitie.titel)) {
                            Label("Link om alleen te kijken", systemImage: "eye")
                        }
                    } else {
                        ProgressView()
                    }
                }
            } header: {
                Text("Delen")
            } footer: {
                if notitie.deling == "gedeeld" { Text("Wie meedoet logt in met Google. De links verlopen na 30 dagen.") }
            }
            .task(id: notitie.deling) {
                if notitie.deling == "gedeeld" { deelToken = await Sync.shared.deel(notitie) }
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

    private var nieuwItemVeld: some View {
        TextField("Nieuw item", text: $nieuwItem)
            .onSubmit(voegToe)
            .submitLabel(.next)
    }

    private func itemRij(_ item: LijstItem) -> some View {
        let weg = doorgestreept.contains(item.persistentModelID)
        return Button { vink(item) } label: {
            HStack {
                Image(systemName: weg ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(weg ? Color.accentColor : Color.secondary)
                Text(item.tekst)
                    .strikethrough(weg)
                    .foregroundStyle(weg ? .secondary : .primary)
                if notitie.groepID != nil {
                    Spacer()
                    ProfielBolletje(id: item.door)
                }
            }
        }
        .accessibilityValue(weg ? "Afgevinkt" : "")
        .accessibilityHint(weg ? "Tik om ongedaan te maken" : "Tik om af te vinken")
    }

    private func zetDeling(_ nieuw: String) {
        if nieuw == "prive" && notitie.deling != "prive" {
            Sync.shared.markeerVerwijderd(notitie)
            notitie.gesynct = nil
        }
        if nieuw != "gedeeld" { notitie.groepID = nil; deelToken = nil }
        notitie.deling = nieuw
        notitie.gewijzigd = Date()
    }

    private func kies(_ tab: String) {
        AppStatus.shared.kiesOpties = notitie.gesorteerdeItems.map(\.tekst)
        AppStatus.shared.kiesTab = tab
        AppStatus.shared.openKiezen = true
    }

    private var deelTekst: String {
        ([notitie.tekst] + notitie.gesorteerdeItems.map { "- \($0.tekst)" } + [notitie.fotoTekst])
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func voegToe() {
        let t = nieuwItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let item = LijstItem(tekst: t, volgorde: (notitie.items.map(\.volgorde).max() ?? -1) + 1)
        item.door = Sync.shared.gebruiker
        notitie.items.append(item)
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
            Ritme.noteer()
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
    @AppStorage("supermarktMeldingen") private var supermarkt = false
    @AppStorage("ontwikkelaar") private var ontwikkelaar = false
    @AppStorage("rust") private var rust = false
    @AppStorage("rustVanaf") private var rustVanaf = 22
    @AppStorage("rustTot") private var rustTot = 7
    @State private var versieTikken = 0
    @State private var vraagVerwijderen = false
    @Query private var plekken: [Plek]
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

            Section("Account") {
                if Sync.shared.gebruiker != nil {
                    LabeledContent("Ingelogd als", value: Sync.shared.naam)
                    if let fout = Sync.shared.fout { Text(fout).font(.footnote).foregroundStyle(.secondary) }
                    Button("Uitloggen") { Task { await Sync.shared.uitloggen() } }
                    Button("Account verwijderen", role: .destructive) { vraagVerwijderen = true }
                        .confirmationDialog("Account en alles in de cloud verwijderen?", isPresented: $vraagVerwijderen, titleVisibility: .visible) {
                            Button("Verwijder alles", role: .destructive) { Task { _ = await Sync.shared.verwijderAccount() } }
                        } message: {
                            Text("Gedeelde lijstjes gaan over naar wie het langst meedoet.")
                        }
                }
            }

            Section {
                Button { Task { await PlekWachter.shared.bewaarHier(naam: String(localized: "Thuis"), soort: "thuis") } } label: {
                    LabeledContent("Huidige plek is Thuis", value: plekken.contains { $0.soort == "thuis" } ? "✓" : "")
                }
                Button { Task { await PlekWachter.shared.bewaarHier(naam: String(localized: "School"), soort: "school") } } label: {
                    LabeledContent("Huidige plek is School", value: plekken.contains { $0.soort == "school" } ? "✓" : "")
                }
                Toggle("Melding bij de supermarkt", isOn: Binding(get: { supermarkt }, set: { supermarkt = $0; PlekWachter.shared.supermarktAan = $0 }))
                ForEach(plekken.filter { $0.soort == "eigen" }) { Label($0.naam, systemImage: "mappin") }
                    .onDelete { i in
                        let eigen = plekken.filter { $0.soort == "eigen" }
                        i.forEach { ctx.delete(eigen[$0]) }
                        PlekWachter.shared.herlaadGebieden()
                    }
            } header: {
                Text("Plekken")
            } footer: {
                Text("Thuis zie je je to-do's, op school je schoolnotities, bij de supermarkt je boodschappen. Alleen als er sinds de vorige keer iets nieuws is.")
            }

            Section {
                Toggle("Trillingen", isOn: $haptiek)
                Toggle("Rustmodus 's avonds", isOn: $rust)
                if rust {
                    Stepper("Vanaf \(rustVanaf):00", value: $rustVanaf, in: 18...23)
                    Stepper("Tot \(rustTot):00", value: $rustTot, in: 5...10)
                }
            } footer: {
                Text("In rustmodus is Kniv donker en rustig, en zwijgen de plekmeldingen.")
            }

            Section { DeelmenuUitleg() }

            Section {
                LabeledContent("Versie", value: VersieInfo.huidig.map { "\($0.mesnaam) · \($0.versie)" } ?? "?")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versieTikken += 1
                        if versieTikken >= 5 { ontwikkelaar.toggle(); versieTikken = 0 }
                    }
                if ontwikkelaar {
                    Label("Schudden om een fout te melden staat aan", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
