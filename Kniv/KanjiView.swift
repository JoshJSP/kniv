import SwiftData
import SwiftUI

/// Kanji uit je eigen Japanse stukjes en bewaarde woorden: kies de goede lezing, daarna zie je de betekenis.
struct KanjiView: View {
    @Query(filter: #Predicate<Leesstuk> { $0.taal == "ja" }) private var stukken: [Leesstuk]
    @Query(filter: #Predicate<BewaardWoord> { $0.taal == "ja" }) private var bewaard: [BewaardWoord]
    @State private var oefenen = false

    private var kaarten: [Kanji.Kaart] {
        var gezien = Set<String>()
        // bewaarde woorden eerst: die wilde je zelf leren, en ze hebben altijd een betekenis
        let eigen = bewaard.flatMap { w in
            Kanji.kaarten(uit: w.woord).map { Kanji.Kaart(woord: $0.woord, lezing: $0.lezing, betekenis: w.betekenis) }
        }
        let uitStukken = stukken.flatMap { Kanji.kaarten(uit: $0.tekst, betekenissen: $0.woorden) }
        return (eigen + uitStukken).filter { gezien.insert($0.woord).inserted }
    }

    var body: some View {
        let lijst = kaarten
        List {
            if lijst.count < 4 {
                ContentUnavailableView("Nog te weinig kanji", systemImage: "character.ja",
                                       description: Text("Lees eerst een paar Japanse stukjes; de kanji daaruit komen hier vanzelf."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    Button { oefenen = true } label: {
                        Label("Oefen \(lijst.count) woorden", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
                Section("Uit je stukjes") {
                    ForEach(lijst, id: \.woord) { k in
                        HStack {
                            Text(verbatim: k.woord).font(.title3)
                            Text(verbatim: k.lezing).foregroundStyle(.secondary)
                            Spacer()
                            Text(verbatim: k.betekenis).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KnivAchtergrond())
        .navigationTitle("Kanji")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $oefenen) { KanjiOefenen(kaarten: lijst) }
    }
}

private struct KanjiOefenen: View {
    let kaarten: [Kanji.Kaart]
    @State private var stapel: Stapel<Kanji.Kaart>
    @State private var opties: [String] = []
    @State private var gekozen: String?
    @Environment(\.dismiss) private var dismiss

    init(kaarten: [Kanji.Kaart]) {
        self.kaarten = kaarten
        _stapel = State(initialValue: Stapel(kaarten.shuffled()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let k = stapel.boven {
                    Text("Nog \(stapel.over)").font(.subheadline).foregroundStyle(.secondary)
                    VStack(spacing: 10) {
                        Text(verbatim: k.woord).font(.system(size: 72))
                        if gekozen != nil {
                            Text(verbatim: k.lezing).font(.title2)
                            if !k.betekenis.isEmpty { Text(verbatim: k.betekenis).foregroundStyle(.secondary) }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .glas(28)
                    .onTapGesture { Voorlezer.shared.lees(k.woord, taal: "ja") }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(opties, id: \.self) { o in
                            Button { kies(o, k) } label: {
                                Text(verbatim: o).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 54)
                            }
                            .buttonStyle(.bordered)
                            .tint(gekozen == nil ? nil : o == k.lezing ? Color.green : o == gekozen ? Color.orange : nil)
                            .disabled(gekozen != nil)
                        }
                    }
                    if gekozen != nil {
                        Button("Volgende") { volgende(k) }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Rondje klaar", systemImage: "checkmark.circle")
                    } description: {
                        Text("Je hebt ze allemaal een keer goed gelezen.")
                    } actions: {
                        Button("Nog een rondje") { stapel = Stapel(kaarten.shuffled()); nieuweOpties() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Spacer()
            }
            .padding(24)
            .background(KnivAchtergrond())
            .toolbar { Button("Klaar") { dismiss() } }
            .onAppear { nieuweOpties() }
        }
    }

    private func kies(_ o: String, _ k: Kanji.Kaart) {
        withAnimation(.snappy) { gekozen = o }
        Voorlezer.shared.lees(k.woord, taal: "ja")
    }

    /// Geen automatische volgende: je wilt de betekenis even kunnen lezen.
    private func volgende(_ k: Kanji.Kaart) {
        withAnimation(.snappy) {
            if gekozen == k.lezing { stapel.wist() } else { stapel.nogEens() }
            gekozen = nil
            nieuweOpties()
        }
    }

    private func nieuweOpties() {
        guard let k = stapel.boven else { opties = []; return }
        var rng = SystemRandomNumberGenerator()
        opties = Kanji.opties(voor: k, uit: kaarten, rng: &rng)
    }
}
