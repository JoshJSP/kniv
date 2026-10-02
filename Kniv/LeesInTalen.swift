import SwiftData
import SwiftUI

/// In een notitie: staat er tekst in een andere taal in (of een link naar zo'n pagina), lees het dan als leesstukje in Talen.
/// Zo werkt "delen naar Kniv" ook voor Talen: deel een artikel of songtekst, open de notitie, tik hierop.
struct LeesInTalenKnop: View {
    let notitie: Notitie
    @Environment(\.modelContext) private var ctx
    @Query private var talen: [GekozenTaal]
    @State private var bezig = false
    @State private var melding: String?

    private var eigenTekst: String { [notitie.tekst, notitie.fotoTekst].joined(separator: "\n") }

    private var link: URL? {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let t = notitie.zoekTekst
        return d.matches(in: t, range: NSRange(t.startIndex..., in: t)).compactMap(\.url).first { $0.scheme?.hasPrefix("http") == true }
    }

    var body: some View {
        let code = Leestaal.vreemd(eigenTekst)
        if code != nil || link != nil {
            Section {
                if let code {
                    Button { maak(code, titel: notitie.titel, tekst: eigenTekst) } label: {
                        Label("Lees als leesstukje (\(Talen.naam(code)))", systemImage: "character.book.closed")
                    }
                } else if let link {
                    Button { Task { await leesPagina(link) } } label: {
                        if bezig { Label("Pagina ophalen…", systemImage: "character.book.closed") }
                        else { Label("Lees deze pagina in Talen", systemImage: "character.book.closed") }
                    }
                    .disabled(bezig)
                }
            } header: {
                Text("Talen")
            } footer: {
                if let melding { Text(verbatim: melding) }
            }
        }
    }

    private func leesPagina(_ url: URL) async {
        bezig = true
        melding = nil
        defer { bezig = false }
        var vraag = URLRequest(url: url, timeoutInterval: 10)
        vraag.setValue("Mozilla/5.0 (iPhone) Kniv", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: vraag),
              let html = String(data: data.prefix(1_000_000), encoding: .utf8) ?? String(data: data.prefix(1_000_000), encoding: .isoLatin1) else {
            melding = String(localized: "De pagina laden lukte niet.")
            return
        }
        let tekst = Leestaal.platteTekst(html)
        guard let code = Leestaal.vreemd(tekst) else {
            melding = String(localized: "Deze pagina is Nederlands of te kort om te lezen.")
            return
        }
        let titel = await Paginatitel.haal(url) ?? url.host() ?? notitie.titel
        maak(code, titel: titel, tekst: tekst)
    }

    private func maak(_ code: String, titel: String, tekst: String) {
        let niveau = talen.first { $0.code == code }.map { Taalniveau.code($0.stap) } ?? "B1"
        let stuk = Leesstuk(taal: code, titel: String(titel.prefix(80)), tekst: String(tekst.prefix(Leestaal.maxTekst)),
                            onderwerp: String(localized: "Gedeeld"), niveau: niveau, woorden: [:])
        ctx.insert(stuk)
        try? ctx.save()
        AppStatus.shared.leesstuk = stuk   // ThuisView opent Talen, TalenView opent het stukje
    }
}
