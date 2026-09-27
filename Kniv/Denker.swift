import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Kniv denkt mee met Apple's taalmodel op het toestel (iOS 26, iPhone 15 Pro en nieuwer). Gratis en privé.
enum Denker {
    static var beschikbaar: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func vraag(_ instructies: String, _ prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let sessie = LanguageModelSession(instructions: instructies)
            return try? await sessie.respond(to: prompt).content
        }
        #endif
        return nil
    }

    /// "pasta carbonara voor 4" → ingrediënten; "4 dagen Barcelona" → paklijst; "verhuizen" → takenlijst.
    static func lijstje(van tekst: String) async -> [String] {
        let antwoord = await vraag("""
            Je maakt praktische afvinklijstjes in de taal van de gebruiker. Antwoord alleen met het lijstje: \
            elke regel begint met "- ", kort, zonder uitleg, maximaal 15 regels. \
            Een gerecht wordt boodschappen met hoeveelheden, een reis wordt een paklijst, een klus wordt stappen.
            """, tekst) ?? ""
        return antwoord.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { NotitieParser.lijstItem($0) ?? ($0.first?.isNumber == true ? $0.drop { $0.isNumber || $0 == "." || $0 == " " }.description : nil) }
            .filter { !$0.isEmpty }
            .prefix(15).map { $0 }
    }

    static func samenvatting(van tekst: String) async -> String? {
        await vraag("Vat de tekst samen in maximaal 5 korte punten die elk beginnen met \"• \". Zelfde taal als de tekst, geen inleiding.",
                    String(tekst.prefix(4000)))
    }
}

/// In het notitiescherm: van gewone tekst een lijstje maken, of een lange foto-tekst samenvatten.
struct DenktMeeSectie: View {
    @Bindable var notitie: Notitie
    @State private var bezig: String?
    @State private var samenvatting: String?

    var body: some View {
        if Denker.beschikbaar && (!notitie.isLijst && !notitie.tekst.isEmpty || notitie.fotoTekst.count > 300) {
            Section {
                if !notitie.isLijst && !notitie.tekst.isEmpty {
                    Button { Task { await maakLijstje() } } label: {
                        Label(bezig == "lijst" ? "Even denken…" : "Maak er een lijstje van", systemImage: "wand.and.stars")
                    }
                    .disabled(bezig != nil)
                }
                if notitie.fotoTekst.count > 300 {
                    if let samenvatting {
                        Text(samenvatting).textSelection(.enabled)
                    } else {
                        Button { Task { await vatSamen() } } label: {
                            Label(bezig == "samen" ? "Even lezen…" : "Vat de foto-tekst samen", systemImage: "text.redaction")
                        }
                        .disabled(bezig != nil)
                    }
                }
            } header: {
                Text("Kniv denkt mee")
            } footer: {
                Text("Op je iPhone zelf, er gaat niets naar internet.")
            }
        }
    }

    private func maakLijstje() async {
        bezig = "lijst"
        let items = await Denker.lijstje(van: notitie.tekst)
        let begin = (notitie.items.map(\.volgorde).max() ?? -1) + 1
        for (i, tekst) in items.enumerated() {
            let item = LijstItem(tekst: tekst, volgorde: begin + i)
            item.door = Sync.shared.gebruiker
            notitie.items.append(item)
        }
        if !items.isEmpty { notitie.gewijzigd = Date() }
        bezig = nil
    }

    private func vatSamen() async {
        bezig = "samen"
        samenvatting = await Denker.samenvatting(van: notitie.fotoTekst)
        bezig = nil
    }
}

/// Bovenaan het startscherm: een rustige, persoonlijke begroeting.
struct Begroeting: View {
    var body: some View {
        let uur = Calendar.current.component(.hour, from: Date())
        let groet: LocalizedStringKey = uur < 6 ? "Goedenacht" : uur < 12 ? "Goedemorgen" : uur < 18 ? "Goedemiddag" : "Goedenavond"
        let voornaam = Sync.shared.naam.split(separator: " ").first.map(String.init) ?? ""
        VStack(alignment: .leading, spacing: 2) {
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline).foregroundStyle(.secondary).textCase(.uppercase)
            HStack(spacing: 6) {
                Text(groet)
                if !voornaam.isEmpty { Text(voornaam) }
            }
            .font(.system(.title, design: .rounded).weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
