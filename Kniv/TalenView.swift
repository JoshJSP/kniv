import SwiftData
import SwiftUI

/// Mesje Talen: per gekozen taal een pagina, met één veeg wissel je.
struct TalenView: View {
    @Query(sort: \GekozenTaal.volgorde) private var talen: [GekozenTaal]
    @AppStorage("talenHuidig") private var huidig = ""
    @State private var kiezen = false
    @State private var open: Leesstuk?

    var body: some View {
        Group {
            if talen.isEmpty {
                ContentUnavailableView {
                    Label("Welke taal wil je leren?", systemImage: "character.bubble")
                } description: {
                    Text("Kies er één of meer. De eerste wordt je hoofdtaal.")
                } actions: {
                    Button("Kies talen") { kiezen = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                TabView(selection: $huidig) {
                    ForEach(talen) { taal in
                        TaalPagina(taal: taal, open: $open).tag(taal.code)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: talen.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .background(KnivAchtergrond())
        .navigationTitle(titel)
        .toolbar {
            Button { kiezen = true } label: {
                Image(systemName: "plus").accessibilityLabel("Kies talen")
            }
        }
        .sheet(isPresented: $kiezen) { TalenKiezer() }
        .navigationDestination(item: $open) { LeesView(stuk: $0) }
        .onChange(of: talen.map(\.code), initial: true) { _, codes in
            if !codes.contains(huidig), let eerste = codes.first { huidig = eerste }
        }
    }

    private var titel: Text {
        if talen.isEmpty { return Text("Talen") }
        return Text(verbatim: Talen.naam(huidig))
    }
}

struct TaalPagina: View {
    @Bindable var taal: GekozenTaal
    @Binding var open: Leesstuk?
    @Environment(\.modelContext) private var ctx
    @Query private var stukken: [Leesstuk]
    @State private var vermogen: TaalVermogen?
    @State private var eigen = ""
    @State private var bezig = false
    @State private var fout: String?

    private let onderwerpen: [(naam: LocalizedStringKey, waarde: String, symbool: String)] = [
        ("Games", "Games", "gamecontroller"),
        ("Internet", "Internet", "network"),
        ("Reizen", "Reizen", "airplane"),
        ("Series", "Series", "tv"),
        ("Muziek", "Muziek", "music.note"),
    ]

    init(taal: GekozenTaal, open: Binding<Leesstuk?>) {
        _taal = Bindable(taal)
        _open = open
        let code = taal.code
        _stukken = Query(filter: #Predicate<Leesstuk> { $0.taal == code }, sort: \Leesstuk.gemaakt, order: .reverse)
    }

    var body: some View {
        List {
            Section {
                Picker("Niveau", selection: Binding(get: { taal.stap }, set: { taal.stap = $0; taal.gewijzigd = Date() })) {
                    ForEach(Taalniveau.codes.indices, id: \.self) { i in
                        Text(verbatim: Taalniveau.codes[i]).tag(i)
                    }
                }
                if let vermogen { VermogenRij(vermogen: vermogen) }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(onderwerpen, id: \.waarde) { o in
                            Button { maak(o.waarde) } label: { Label(o.naam, systemImage: o.symbool) }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .listRowInsets(EdgeInsets())
                .disabled(bezig)
                HStack {
                    TextField("Eigen onderwerp, bv. Minecraft", text: $eigen)
                        .submitLabel(.go)
                        .onSubmit { maak(eigen) }
                    Button("Maak") { maak(eigen) }
                        .buttonStyle(.borderless)
                        .disabled(bezig || Stukje.schoon(onderwerp: eigen).isEmpty)
                }
                if bezig {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Stukje schrijven…").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Nieuw stukje")
            } footer: {
                if let fout { Text(fout) }
            }

            if !stukken.isEmpty {
                Section("Eerder gelezen") {
                    ForEach(stukken) { stuk in
                        Button { open = stuk } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stuk.titel).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(verbatim: "\(stuk.niveau) · \(stuk.gemaakt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { plekken in
                        for i in plekken { Sync.shared.markeerVerwijderd(stukken[i]); ctx.delete(stukken[i]) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 44, for: .scrollContent)
        .task(id: taal.code) { vermogen = await TaalDienst.vermogen(taal.code) }
    }

    private func maak(_ onderwerp: String) {
        let schoon = Stukje.schoon(onderwerp: onderwerp)
        guard !schoon.isEmpty, !bezig else { return }
        let code = taal.code
        let niveau = Taalniveau.code(taal.stap)
        bezig = true
        fout = nil
        Task {
            defer { bezig = false }
            do {
                var v = vermogen
                if v == nil { v = await TaalDienst.vermogen(code) }
                let s = try await TaalDienst.nieuwStukje(taal: code, niveau: niveau, onderwerp: schoon, vermogen: v ?? .niets)
                let stuk = Leesstuk(taal: code, titel: s.titel, tekst: s.tekst, onderwerp: schoon, niveau: niveau, woorden: s.woorden)
                ctx.insert(stuk)
                try? ctx.save()
                eigen = ""
                open = stuk
            } catch let f as TaalDienst.Fout {
                fout = f.melding
            } catch {
                fout = TaalDienst.Fout.mislukt.melding
            }
        }
    }
}

/// Wat deze taal op deze iPhone kan, in gewone woorden.
struct VermogenRij: View {
    let vermogen: TaalVermogen

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vermogen.tekstBron == .toestel {
                Label("Stukjes maakt je iPhone zelf, ook offline", systemImage: "iphone")
            } else {
                Label("Stukjes komen via internet en tellen mee voor de daglimiet", systemImage: "network")
            }
            if vermogen.stem {
                Label("Je iPhone kan voorlezen", systemImage: "speaker.wave.2")
            } else {
                Label("Geen stem voor deze taal: alleen lezen", systemImage: "speaker.slash")
            }
            if vermogen.tekstBron == .online && !Denker.beschikbaar {
                Label("Tip: met Apple Intelligence aan maakt je iPhone voor veel talen zelf stukjes.", systemImage: "sparkles")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }
}

struct TaalCode: Identifiable { let id: String }

/// Alle talen, met zoekbalk. Tik om toe te voegen of weg te halen.
struct TalenKiezer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \GekozenTaal.volgorde) private var talen: [GekozenTaal]
    @AppStorage("talenHuidig") private var huidig = ""
    @State private var alle: [(code: String, naam: String)] = []
    @State private var zoek = ""
    @State private var nieuw: TaalCode?
    @State private var weg: GekozenTaal?

    private var lijst: [(code: String, naam: String)] {
        zoek.isEmpty ? alle : Talen.zoek(zoek, in: alle)
    }

    var body: some View {
        NavigationStack {
            List(lijst, id: \.code) { t in
                let gekozen = talen.first { $0.code == t.code }
                Button {
                    if let gekozen { weg = gekozen } else { nieuw = TaalCode(id: t.code) }
                } label: {
                    HStack {
                        Text(t.naam).foregroundStyle(.primary)
                        Spacer()
                        if gekozen != nil {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityAddTraits(gekozen != nil ? .isSelected : [])
            }
            .searchable(text: $zoek, prompt: "Zoek een taal")
            .navigationTitle("Talen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
            .onAppear { if alle.isEmpty { alle = Talen.alle() } }
            .sheet(item: $nieuw) { code in
                NiveauKeuze(code: code) { stap in voegToe(code.id, stap: stap) }
            }
            .confirmationDialog(
                Text("Verwijder \(wegNaam) uit je talen?"),
                isPresented: Binding(get: { weg != nil }, set: { if !$0 { weg = nil } }),
                titleVisibility: .visible,
                presenting: weg
            ) { taal in
                Button("Verwijder", role: .destructive) { Sync.shared.markeerVerwijderd(taal); ctx.delete(taal) }
            } message: { _ in
                Text("Je stukjes blijven bewaard.")
            }
        }
    }

    private var wegNaam: String { weg.map { Talen.naam($0.code) } ?? "" }

    private func voegToe(_ code: String, stap: Int) {
        guard !talen.contains(where: { $0.code == code }) else { return }
        ctx.insert(GekozenTaal(code: code, stap: stap, volgorde: (talen.map(\.volgorde).max() ?? -1) + 1))
        try? ctx.save()
        huidig = code
    }
}

/// Startniveau kiezen, in gewone woorden.
struct NiveauKeuze: View {
    let code: TaalCode
    let kies: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hoe goed ken je \(Talen.naam(code.id)) al?")
                    .font(.title2.bold())
                    .padding(.bottom, 6)
                ForEach(Taalniveau.startKeuzes, id: \.stap) { keuze in
                    Button {
                        kies(keuze.stap)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(verbatim: keuze.code)
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                                .frame(minWidth: 34, alignment: .leading)
                            uitleg(keuze.stap)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .glas(20)
                    }
                    .buttonStyle(.plain)
                }
                Text("Twijfel je? Kies lager. Na elk stukje schuift je niveau mee.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .background(KnivAchtergrond())
        .presentationDragIndicator(.visible)
    }

    private func uitleg(_ stap: Int) -> Text {
        switch stap {
        case 0: return Text("Bijna niks: losse woordjes en korte zinnen")
        case 2: return Text("Een beetje: simpele zinnen over dagelijkse dingen")
        case 4: return Text("Redelijk: een rustig verhaal volgen")
        case 6: return Text("Goed: series met ondertitels in die taal")
        case 8: return Text("Heel goed: bijna alles, ook snelle gesprekken")
        default: return Text(verbatim: "")
        }
    }
}
