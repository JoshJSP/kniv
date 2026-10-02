import SwiftData
import SwiftUI

/// Al je Kniv-gegevens als één leesbaar Markdown-bestand: jouw data, van jou.
enum Export {
    @MainActor static func markdown() -> String {
        let ctx = KnivOpslag.container.mainContext
        let notities = ((try? ctx.fetch(FetchDescriptor<Notitie>(sortBy: [SortDescriptor(\.gemaakt, order: .reverse)]))) ?? []).filter { !$0.isVerzegeld }
        let timers = (try? ctx.fetch(FetchDescriptor<KnivTimer>())) ?? []
        let potten = (try? ctx.fetch(FetchDescriptor<Pot>())) ?? []
        let datum = Date.FormatStyle(date: .abbreviated, time: .shortened)
        var md = "# Kniv\n\n" + String(localized: "Geëxporteerd op \(Date().formatted(datum))") + "\n"

        for (bakje, lijst) in Dictionary(grouping: notities, by: { $0.bakjeNaam ?? String(localized: "Nog niet gesorteerd") }).sorted(by: { $0.key < $1.key }) {
            md += "\n## \(bakje)\n"
            for n in lijst {
                md += "\n### \(n.titel)\n_\(n.gemaakt.formatted(datum))_\n\n"
                if !n.tekst.isEmpty { md += n.tekst + "\n" }
                for item in n.lijstVolgorde { md += "- [ ] \(item.tekst)\n" }
                if !n.fotoTekst.isEmpty { md += "\n> " + n.fotoTekst.replacingOccurrences(of: "\n", with: "\n> ") + "\n" }
            }
        }
        let countdowns = timers.filter(\.isCountdown)
        if !countdowns.isEmpty {
            md += "\n## " + String(localized: "Countdowns") + "\n"
            for c in countdowns { md += "- \(c.naam): \(c.doel?.formatted(date: .long, time: .omitted) ?? "")\n" }
        }
        for p in potten {
            md += "\n## " + String(localized: "Potje") + ": \(p.naam)\n"
            for u in p.uitgaven.sorted(by: { $0.datum < $1.datum }) {
                md += "- \(u.omschrijving.isEmpty ? String(localized: "Uitgave") : u.omschrijving): \(Omzetter.euro(u.bedrag, p.valuta)) (\(u.betaaldDoor))\n"
            }
            for b in Afrekenen.minsteBetalingen(p.saldi) { md += "- **\(b.van) → \(b.naar): \(Omzetter.euro(b.bedrag, p.valuta))**\n" }
        }
        return md
    }

    @MainActor static func bestand() -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "Kniv-\(Focuslog.dagSleutel(Date())).md")
        return (try? markdown().write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}

struct ExportKnop: View {
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                ShareLink(item: url) { Label("Deel of bewaar je export", systemImage: "square.and.arrow.up") }
            } else {
                Button { url = Export.bestand() } label: { Label("Exporteer alles", systemImage: "doc.text") }
            }
        }
    }
}
