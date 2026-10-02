import AppIntents
import SwiftUI
import UniformTypeIdentifiers

/// "Bewaar in Kniv": tekst, een link of een foto vanuit elke app. Zonder deelextensie (die kost een app-ID in SideStore);
/// in Opdrachten zet je hem met "Toon in deelmenu" in het deelmenu.
struct BewaarInKnivIntent: AppIntent {
    static var title: LocalizedStringResource = "Bewaar in Kniv"
    static var description = IntentDescription("Bewaart tekst, een link of een foto in Kniv en sorteert het in het juiste bakje.")
    static var openAppWhenRun = false

    @Parameter(title: "Tekst") var tekst: String?
    @Parameter(title: "Link") var link: URL?
    @Parameter(title: "Foto", supportedContentTypes: [.image]) var foto: IntentFile?

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KnivOpslag.container.mainContext
        KnivOpslag.zaaiBakjes()
        var regels: [String] = []
        if let tekst, !tekst.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { regels.append(tekst) }
        if let link {
            let titel = await Paginatitel.haal(link)
            regels.append([titel, link.absoluteString].compactMap { $0 }.joined(separator: "\n"))
        }
        var bestand: String?
        var fotoTekst = ""
        if let foto, let beeld = UIImage(data: foto.data) {
            bestand = Fotos.bewaar(beeld)
            fotoTekst = await TekstHerkenning.lees(beeld)
        }
        guard let n = Vastlegger.bewaar(regels.joined(separator: "\n"), bron: bestand == nil ? .siri : .foto,
                                        foto: bestand, fotoTekst: fotoTekst, in: ctx) else {
            return .result(dialog: "Er viel niks te bewaren.")
        }
        await Vastlegger.sorteer(n, in: ctx)
        if let tekst, Leestaal.vreemd(tekst) != nil {
            return .result(dialog: "Bewaard. Open de notitie in Kniv om hem als leesstukje in Talen te lezen.")
        }
        return .result(dialog: n.bakjeNaam.map { "Bewaard in \($0)." } ?? "Bewaard in Kniv.")
    }
}

enum Paginatitel {
    /// De <title> van een webpagina, zodat een gedeelde link meteen leesbaar is.
    static func haal(_ url: URL) async -> String? {
        var vraag = URLRequest(url: url, timeoutInterval: 5)
        vraag.setValue("Mozilla/5.0 (iPhone) Kniv", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: vraag),
              let html = String(data: data.prefix(200_000), encoding: .utf8) ?? String(data: data.prefix(200_000), encoding: .isoLatin1),
              let m = Herinnering.eersteMatch(#"(?is)<title[^>]*>(.*?)</title>"#, in: html) else { return nil }
        let titel = m[1]
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"").trimmingCharacters(in: .whitespacesAndNewlines)
        return titel.isEmpty ? nil : String(titel.prefix(140))
    }
}

/// Korte uitleg in Instellingen: zo zet je Kniv in het deelmenu.
struct DeelmenuUitleg: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kniv in je deelmenu").font(.headline)
            Text("Open Opdrachten → + → Voeg actie toe → Kniv → Bewaar in Kniv. Tik op ⓘ en zet **Toon in deelmenu** aan. Daarna staat Kniv onder Deel in elke app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link(destination: URL(string: "shortcuts://")!) { Label("Open Opdrachten", systemImage: "square.2.layers.3d") }
                .font(.footnote)
        }
    }
}
