import SwiftData
import SwiftUI

/// Vastgepinde notities, bovenaan Vastleggen.
struct VastgepindRij: View {
    @Query(filter: #Predicate<Notitie> { $0.vastgepind == true && $0.weggegooid == nil }, sort: \Notitie.gewijzigd, order: .reverse)
    private var vast: [Notitie]

    var body: some View {
        if !vast.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Vastgepind", systemImage: "pin.fill").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vast) { n in NavigationLink(value: n) { NotitieKaart(notitie: n) }.buttonStyle(.plain) }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}

/// Weggegooide notities blijven 30 dagen bewaard.
struct PrullenbakView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Notitie> { $0.weggegooid != nil }, sort: \Notitie.gewijzigd, order: .reverse)
    private var weg: [Notitie]

    var body: some View {
        List {
            if weg.isEmpty {
                ContentUnavailableView("Prullenbak is leeg", systemImage: "trash", description: Text("Weggegooide notities blijven hier 30 dagen."))
                    .listRowBackground(Color.clear)
            }
            ForEach(weg) { n in
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.titel).lineLimit(1)
                    if let d = n.weggegooid {
                        Text("Weg over \(max(0, 30 - (Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0))) dagen")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { Prullenbak.zetTerug(n) } label: { Label("Terugzetten", systemImage: "arrow.uturn.backward") }.tint(.green)
                }
                .swipeActions {
                    Button(role: .destructive) { Vastlegger.verwijder(n, in: ctx, uitCloud: false) } label: { Label("Definitief weg", systemImage: "trash") }
                }
            }
            if !weg.isEmpty {
                Button("Prullenbak legen", role: .destructive) { weg.forEach { Vastlegger.verwijder($0, in: ctx, uitCloud: false) } }
            }
        }
        .navigationTitle("Prullenbak")
    }
}

enum Prullenbak {
    /// Naar de prullenbak: uit beeld, en op andere apparaten meteen weg (terugzetten zet hem daar weer terug).
    @MainActor static func gooi(_ n: Notitie) {
        if n.deling != "prive" { Sync.shared.markeerVerwijderd(n) }
        n.weggegooid = Date()
        Herinneraar.trekIn(n.uid)
        n.vastgepind = false
        n.gesynct = .distantFuture      // niet opnieuw sturen zolang hij in de prullenbak ligt
    }

    @MainActor static func zetTerug(_ n: Notitie) {
        n.weggegooid = nil
        n.gesynct = nil           // gaat opnieuw naar de cloud
        n.gewijzigd = Date()
    }

    /// Bij het opstarten: alles dat langer dan 30 dagen in de prullenbak ligt, echt weg.
    @MainActor static func ruimOp() {
        let ctx = KnivOpslag.container.mainContext
        let grens = Date().addingTimeInterval(-30 * 86_400)
        for n in (try? ctx.fetch(FetchDescriptor<Notitie>())) ?? [] where (n.weggegooid ?? .distantFuture) < grens {
            Vastlegger.verwijder(n, in: ctx, uitCloud: false)
        }
    }
}
