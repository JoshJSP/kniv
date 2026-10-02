import SwiftUI

/// Kana leren: kies hiragana of katakana en welke rijen, dan per teken de goede uitspraak kiezen.
struct KanaView: View {
    @AppStorage("kanaSchrift") private var schrift: Kana.Schrift = .hiragana
    @AppStorage("kanaRijen") private var rijenTekst = "a,ka,sa"
    @State private var oefenen = false

    private var gekozen: Set<String> { Set(rijenTekst.split(separator: ",").map(String.init)) }

    var body: some View {
        List {
            Section {
                Picker("Schrift", selection: $schrift) {
                    Text(verbatim: "ひらがな hiragana").tag(Kana.Schrift.hiragana)
                    Text(verbatim: "カタカナ katakana").tag(Kana.Schrift.katakana)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Kana.rijen, id: \.naam) { rij in
                    Button { wissel(rij.naam) } label: {
                        HStack {
                            Image(systemName: gekozen.contains(rij.naam) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(gekozen.contains(rij.naam) ? Color.accentColor : Color.secondary)
                            Text(verbatim: rij.tekens.map { Kana.inSchrift($0, schrift).kana }.joined(separator: " "))
                                .font(.title3).foregroundStyle(.primary)
                            Spacer()
                            Text(verbatim: rij.tekens.map(\.romaji).joined(separator: " "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Welke rijen?")
            } footer: {
                Text("Begin met een paar rijen en zet er meer aan als ze goed gaan.")
            }
            Section {
                Button { oefenen = true } label: {
                    Label("Oefen", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(gekozen.isEmpty)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(KnivAchtergrond())
        .navigationTitle("Kana leren")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $oefenen) {
            KanaOefenen(tekens: Kana.tekens(rijen: gekozen, schrift: schrift))
        }
    }

    private func wissel(_ naam: String) {
        var g = gekozen
        if g.contains(naam) { g.remove(naam) } else { g.insert(naam) }
        // volgorde van de rijen aanhouden
        rijenTekst = Kana.rijen.map(\.naam).filter(g.contains).joined(separator: ",")
    }
}

private struct KanaOefenen: View {
    let tekens: [Kana.Teken]
    @State private var stapel: Stapel<Kana.Teken>
    @State private var opties: [String] = []
    @State private var gekozen: String?
    @Environment(\.dismiss) private var dismiss

    init(tekens: [Kana.Teken]) {
        self.tekens = tekens
        _stapel = State(initialValue: Stapel(tekens.shuffled()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                if let t = stapel.boven {
                    Text("Nog \(stapel.over)").font(.subheadline).foregroundStyle(.secondary)
                    Button { Voorlezer.shared.lees(t.kana, taal: "ja") } label: {
                        Text(verbatim: t.kana).font(.system(size: 110))
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .glas(28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Tik om het te horen")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(opties, id: \.self) { o in
                            Button { kies(o, t) } label: {
                                Text(verbatim: o).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 54)
                            }
                            .buttonStyle(.bordered)
                            .tint(kleur(o, t))
                            .disabled(gekozen != nil)
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Rondje klaar", systemImage: "checkmark.circle")
                    } description: {
                        Text("Je hebt ze allemaal een keer goed gehad.")
                    } actions: {
                        Button("Nog een rondje") { stapel = Stapel(tekens.shuffled()); nieuweOpties() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Spacer()
            }
            .padding(24)
            .background(KnivAchtergrond())
            .toolbar { Button("Klaar") { dismiss() } }
            .onAppear { nieuweOpties() }
            .sensoryFeedback(.selection, trigger: gekozen)
        }
    }

    private func kleur(_ o: String, _ t: Kana.Teken) -> Color? {
        guard let gekozen else { return nil }
        if o == t.romaji { return .green }
        return o == gekozen ? .orange : nil
    }

    private func kies(_ o: String, _ t: Kana.Teken) {
        gekozen = o
        let goed = o == t.romaji
        Task {
            try? await Task.sleep(for: .milliseconds(goed ? 500 : 1300))
            withAnimation(.snappy) {
                if goed { stapel.wist() } else { stapel.nogEens() }
                gekozen = nil
                nieuweOpties()
            }
        }
    }

    private func nieuweOpties() {
        guard let t = stapel.boven else { opties = []; return }
        var rng = SystemRandomNumberGenerator()
        opties = Kana.opties(voor: t, pool: tekens, rng: &rng)
    }
}
