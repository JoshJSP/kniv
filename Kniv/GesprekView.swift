import SwiftUI

/// Gesprekje in de doeltaal: typen of inspreken, Kniv praat terug (en leest dat voor) en geeft af en toe een tip.
struct GesprekView: View {
    let taal: String
    let niveau: String
    @AppStorage("gesprekVoorlezen") private var voorlezen = true
    @StateObject private var spraak = Spraak()
    @State private var onderwerp = ""
    @State private var begonnen = false
    @State private var beurten: [Gesprek.Beurt] = []
    @State private var tips: [Int: String] = [:]   // index van jouw beurt → tip
    @State private var invoer = ""
    @State private var bezig = false
    @State private var fout: String?
    @State private var vermogen: TaalVermogen?

    private let voorstellen = ["Je dag", "Eten", "Reizen", "Games", "Muziek", "Het weer", "Je weekend"]

    var body: some View {
        Group {
            if begonnen { gesprek } else { start }
        }
        .background(KnivAchtergrond())
        .navigationTitle("Gesprekje")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Toggle(isOn: $voorlezen) { Image(systemName: voorlezen ? "speaker.wave.2.fill" : "speaker.slash") }
                .accessibilityLabel("Antwoorden voorlezen")
        }
        .task(id: taal) { vermogen = await TaalDienst.vermogen(taal) }
        .onDisappear {
            Voorlezer.shared.stop()
            Task { _ = await spraak.stop() }
        }
    }

    // MARK: begin

    private var start: some View {
        List {
            Section {
                Text("Praat met Kniv in het \(Talen.naam(taal)), op jouw niveau (\(niveau)). Typ of spreek in; zit er een fout in, dan krijg je een tip in het Nederlands.")
                    .foregroundStyle(.secondary)
            }
            Section("Waarover?") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(voorstellen, id: \.self) { v in
                            Button(LocalizedStringKey(v)) { onderwerp = v }   // het model snapt het Nederlandse onderwerp prima
                                .buttonStyle(.bordered)
                        }
                    }
                }
                TextField("Of een eigen onderwerp", text: $onderwerp)
            }
            Section {
                Button { Task { await begin() } } label: {
                    Label("Begin het gesprek", systemImage: "bubble.left.and.bubble.right.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vermogen == nil || bezig)
            } footer: {
                if let fout { Text(verbatim: fout) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func begin() async {
        if onderwerp.trimmingCharacters(in: .whitespaces).isEmpty { onderwerp = String(localized: "Je dag") }
        begonnen = true
        await volgende()
    }

    // MARK: gesprek

    private var gesprek: some View {
        ScrollViewReader { lezer in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(beurten.indices, id: \.self) { i in
                        bubbel(beurten[i], tip: tips[i]).id(i)
                    }
                    if bezig { ProgressView().padding(.leading, 12).id(-1) }
                    if let fout { Text(verbatim: fout).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(16)
            }
            .onChange(of: beurten.count) { withAnimation { lezer.scrollTo(beurten.count - 1, anchor: .bottom) } }
            .safeAreaInset(edge: .bottom) { invoerBalk }
        }
    }

    private func bubbel(_ b: Gesprek.Beurt, tip: String?) -> some View {
        let vanMij = b.rol == .ik
        return VStack(alignment: vanMij ? .trailing : .leading, spacing: 4) {
            Text(verbatim: b.tekst)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(vanMij ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                .onTapGesture { if !vanMij { Voorlezer.shared.lees(b.tekst, taal: taal) } }
            if let tip, !tip.isEmpty {
                Label { Text(verbatim: tip) } icon: { Image(systemName: "lightbulb") }
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: vanMij ? .trailing : .leading)
    }

    private var invoerBalk: some View {
        HStack(spacing: 10) {
            Button { Task { await microfoon() } } label: {
                Image(systemName: spraak.bezig ? "stop.fill" : "mic.fill")
                    .frame(width: 44, height: 44)
                    .background(spraak.bezig ? Color.red.opacity(0.85) : Color.secondary.opacity(0.18), in: Circle())
                    .foregroundStyle(spraak.bezig ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spraak.bezig ? Text("Stop met inspreken") : Text("Inspreken"))
            TextField("Zeg iets…", text: spraak.bezig ? .constant(spraak.tekst) : $invoer, axis: .vertical)
                .lineLimit(1...4)
                .padding(10)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                .onSubmit { Task { await stuur() } }
            Button { Task { await stuur() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(bezig || invoer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Stuur")
        }
        .padding(10)
        .glas(28)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func microfoon() async {
        if spraak.bezig {
            invoer = await spraak.stop()
            if !invoer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await stuur() }
            return
        }
        Voorlezer.shared.stop()
        fout = nil
        do { try await spraak.start(taal: taal) }
        catch Spraak.Fout.geenToestemming {
            fout = String(localized: "Kniv mag de microfoon of spraakherkenning nog niet gebruiken. Zet het aan bij Instellingen › Kniv.")
        } catch Spraak.Fout.geenHerkenner {
            fout = String(localized: "Je iPhone kan deze taal (nog) niet verstaan. Typen kan wel.")
        } catch {
            fout = String(localized: "De microfoon starten lukte niet. Probeer het nog eens.")
        }
    }

    private func stuur() async {
        let zin = invoer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zin.isEmpty, !bezig else { return }
        invoer = ""
        beurten.append(Gesprek.Beurt(rol: .ik, tekst: zin))
        await volgende()
    }

    private func volgende() async {
        guard let vermogen else { return }
        bezig = true
        fout = nil
        defer { bezig = false }
        do {
            let a = try await TaalDienst.gesprek(beurten, onderwerp: onderwerp, taal: taal, niveau: niveau, vermogen: vermogen)
            if !a.tip.isEmpty, let laatste = beurten.lastIndex(where: { $0.rol == .ik }) { tips[laatste] = a.tip }
            beurten.append(Gesprek.Beurt(rol: .kniv, tekst: a.antwoord))
            if voorlezen { Voorlezer.shared.lees(a.antwoord, taal: taal) }
        } catch {
            fout = (error as? TaalDienst.Fout ?? .mislukt).melding
        }
    }
}
