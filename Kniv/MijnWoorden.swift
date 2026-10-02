import SwiftData
import SwiftUI

/// Mijn woorden: alles wat je bij een leesstukje bewaarde, per taal, met kaartjes om te oefenen.
struct MijnWoordenView: View {
    let taal: String
    @Environment(\.modelContext) private var ctx
    @Query private var woorden: [BewaardWoord]
    @State private var oefenen = false

    init(taal: String) {
        self.taal = taal
        _woorden = Query(filter: #Predicate<BewaardWoord> { $0.taal == taal }, sort: \BewaardWoord.gemaakt, order: .reverse)
    }

    var body: some View {
        List {
            if woorden.isEmpty {
                ContentUnavailableView("Nog geen woorden", systemImage: "text.book.closed",
                                       description: Text("Tik in een leesstukje op een woord en kies Bewaar in Mijn woorden."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    Button { oefenen = true } label: {
                        Label("Oefen met kaartjes", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
                Section {
                    ForEach(woorden) { w in
                        Button { Voorlezer.shared.lees(w.woord, taal: taal) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(verbatim: w.woord).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    if let lezing = Woorden.lezing(w.woord, taal: taal) {
                                        Text(verbatim: lezing).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                if !w.betekenis.isEmpty { Text(verbatim: w.betekenis).foregroundStyle(.secondary) }
                                if !w.zin.isEmpty { Text(verbatim: w.zin).font(.footnote).foregroundStyle(.tertiary).lineLimit(2) }
                            }
                        }
                        .accessibilityHint("Tik om het woord te horen")
                    }
                    .onDelete { plekken in
                        for i in plekken {
                            Sync.shared.markeerVerwijderd(woorden[i])
                            ctx.delete(woorden[i])
                        }
                        try? ctx.save()
                    }
                } footer: {
                    Text("Tik op een woord om het te horen. Veeg naar links om het weg te halen.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KnivAchtergrond())
        .navigationTitle("Mijn woorden")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $oefenen) { KaartjesView(woorden: woorden.shuffled(), taal: taal) }
    }
}

/// Kaartjes: voorkant het woord, tik om te draaien naar betekenis en zin.
struct KaartjesView: View {
    let taal: String
    @State private var stapel: Stapel<PersistentIdentifier>
    @State private var omgedraaid = false
    @Environment(\.dismiss) private var dismiss
    private let opID: [PersistentIdentifier: BewaardWoord]
    private let alle: [BewaardWoord]

    init(woorden: [BewaardWoord], taal: String) {
        self.taal = taal
        alle = woorden
        opID = Dictionary(woorden.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { a, _ in a })
        _stapel = State(initialValue: Stapel(woorden.map(\.persistentModelID)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let id = stapel.boven, let w = opID[id] {
                    Text("Nog \(stapel.over)").font(.subheadline).foregroundStyle(.secondary)
                    kaart(w)
                        .onTapGesture { withAnimation(.snappy) { omgedraaid.toggle() } }
                    if omgedraaid {
                        HStack(spacing: 14) {
                            Button { volgende { stapel.nogEens() } } label: {
                                Label("Nog eens", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button { volgende { stapel.wist() } } label: {
                                Label("Wist ik", systemImage: "checkmark").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .controlSize(.large)
                    } else {
                        Text("Tik op het kaartje om te draaien.").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Rondje klaar", systemImage: "checkmark.circle")
                    } description: {
                        Text("Je kende ze allemaal een keer.")
                    } actions: {
                        Button("Nog een rondje") {
                            withAnimation(.snappy) { stapel = Stapel(alle.shuffled().map(\.persistentModelID)) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Spacer()
            }
            .padding(24)
            .background(KnivAchtergrond())
            .toolbar { Button("Klaar") { dismiss() } }
        }
    }

    private func kaart(_ w: BewaardWoord) -> some View {
        VStack(spacing: 12) {
            if omgedraaid {
                Text(verbatim: w.betekenis.isEmpty ? "—" : w.betekenis).font(.title.bold()).multilineTextAlignment(.center)
                if !w.zin.isEmpty { Text(verbatim: w.zin).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            } else {
                Text(verbatim: w.woord).font(.largeTitle.bold()).multilineTextAlignment(.center)
                if let lezing = Woorden.lezing(w.woord, taal: taal) { Text(verbatim: lezing).font(.title3).foregroundStyle(.secondary) }
                Button { Voorlezer.shared.lees(w.woord, taal: taal) } label: { Label("Luister", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(24)
        .glas(28)
    }

    private func volgende(_ actie: () -> Void) {
        withAnimation(.snappy) {
            actie()
            omgedraaid = false
        }
    }
}
