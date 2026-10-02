import SwiftUI

// Oefenen onder een leesstukje: vragen over de tekst, zelf een zin schrijven en naspreken.
// Geen punten of reeksen (zie het ontwerp van Talen): alleen laten zien wat goed ging.

/// Drie meerkeuzevragen over de tekst, pas gemaakt als je erom vraagt.
struct VragenBlok: View {
    let stuk: Leesstuk
    let vermogen: TaalVermogen
    @State private var vragen: [Oefenen.Vraag] = []
    @State private var gekozen: [Int: Int] = [:]
    @State private var bezig = false
    @State private var fout: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vragen over de tekst").font(.headline)
            if vragen.isEmpty {
                Button { Task { await maak() } } label: {
                    if bezig { Label("Even denken…", systemImage: "questionmark.bubble") }
                    else { Label("Stel me een paar vragen", systemImage: "questionmark.bubble") }
                }
                .buttonStyle(.bordered)
                .disabled(bezig)
            }
            ForEach(vragen.indices, id: \.self) { i in
                let v = vragen[i]
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: v.vraag).font(.body.weight(.semibold))
                    ForEach(v.opties.indices, id: \.self) { o in
                        Button { withAnimation(.snappy) { gekozen[i] = o } } label: {
                            HStack {
                                Text(verbatim: v.opties[o]).multilineTextAlignment(.leading)
                                Spacer()
                                if let k = gekozen[i], o == v.goed || o == k {
                                    Image(systemName: o == v.goed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(o == v.goed ? Color.green : Color.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .disabled(gekozen[i] != nil)
                    }
                }
            }
            if let fout { Text(verbatim: fout).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glas(22)
    }

    private func maak() async {
        bezig = true
        fout = nil
        defer { bezig = false }
        do {
            vragen = try await TaalDienst.vragen(bij: stuk.tekst, taal: stuk.taal, niveau: stuk.niveau, vermogen: vermogen)
            gekozen = [:]
        } catch {
            fout = (error as? TaalDienst.Fout ?? .mislukt).melding
        }
    }
}

/// Zelf een zin schrijven over het stukje; Kniv kijkt hem na en legt in het Nederlands uit wat beter kan.
struct SchrijfBlok: View {
    let stuk: Leesstuk
    let vermogen: TaalVermogen
    @State private var zin = ""
    @State private var uitkomst: Oefenen.Verbetering?
    @State private var bezig = false
    @State private var fout: String?
    @FocusState private var typt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schrijf zelf iets").font(.headline)
            Text("Schrijf een zin in het \(Talen.naam(stuk.taal)) over dit stukje. Kniv kijkt hem na.")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("Jouw zin", text: $zin, axis: .vertical)
                .lineLimit(2...5)
                .focused($typt)
                .padding(10)
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .disabled(uitkomst != nil)
            if let uitkomst {
                VStack(alignment: .leading, spacing: 6) {
                    if uitkomst.goed {
                        Label("Goed zo, daar klopt alles aan.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text(verbatim: uitkomst.verbeterd).font(.body.weight(.semibold))
                    }
                    if !uitkomst.uitleg.isEmpty { Text(verbatim: uitkomst.uitleg).font(.subheadline).foregroundStyle(.secondary) }
                }
                Button("Nog een zin") {
                    withAnimation(.snappy) { self.uitkomst = nil; zin = "" }
                    typt = true
                }
                .buttonStyle(.bordered)
            } else {
                Button { Task { await kijkNa() } } label: {
                    if bezig { Label("Even kijken…", systemImage: "pencil.and.outline") }
                    else { Label("Kijk na", systemImage: "pencil.and.outline") }
                }
                .buttonStyle(.bordered)
                .disabled(bezig || zin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let fout { Text(verbatim: fout).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glas(22)
    }

    private func kijkNa() async {
        typt = false
        bezig = true
        fout = nil
        defer { bezig = false }
        do {
            let u = try await TaalDienst.verbeter(zin, onderwerp: stuk.titel, taal: stuk.taal, niveau: stuk.niveau, vermogen: vermogen)
            withAnimation(.snappy) { uitkomst = u }
        } catch {
            fout = (error as? TaalDienst.Fout ?? .mislukt).melding
        }
    }
}

/// Een zin uit het stukje naspreken: eerst luisteren, dan zelf zeggen. Groen = verstaan, oranje = nog eens.
struct SpreekBlok: View {
    let stuk: Leesstuk
    @StateObject private var spraak = Spraak()
    @State private var index = 0
    @State private var uitslag: [Oefenen.Nagezegd]?
    @State private var fout: String?

    private var zinnen: [String] { Oefenen.zinnen(uit: stuk.tekst, taal: stuk.taal) }

    var body: some View {
        let lijst = zinnen
        if !lijst.isEmpty {
            let zin = lijst[index % lijst.count]
            VStack(alignment: .leading, spacing: 12) {
                Text("Zeg het na").font(.headline)
                if let uitslag {
                    Text(gekleurd(uitslag)).font(.title3)
                    Text(oordeel(uitslag)).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: zin).font(.title3)
                }
                if spraak.bezig, !spraak.tekst.isEmpty {
                    Text(verbatim: spraak.tekst).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Button { luister(zin) } label: { Label("Luister", systemImage: "speaker.wave.2.fill") }
                        .buttonStyle(.bordered)
                        .disabled(spraak.bezig)
                    Button { Task { await microfoon(zin) } } label: {
                        if spraak.bezig { Label("Klaar", systemImage: "stop.fill") }
                        else { Label("Zeg het", systemImage: "mic.fill") }
                    }
                    .buttonStyle(.borderedProminent)
                    if lijst.count > 1 {
                        Button {
                            withAnimation(.snappy) { index += 1; uitslag = nil }
                        } label: { Label("Volgende", systemImage: "arrow.right") }
                            .buttonStyle(.bordered)
                            .disabled(spraak.bezig)
                    }
                }
                .font(.subheadline)
                if let fout { Text(verbatim: fout).font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glas(22)
            .onDisappear { Task { _ = await spraak.stop() } }
        }
    }

    private func luister(_ zin: String) {
        Voorlezer.shared.lees(zin, taal: stuk.taal, snelheid: 0.85)
    }

    private func microfoon(_ zin: String) async {
        if spraak.bezig {
            let gehoord = await spraak.stop()
            withAnimation(.snappy) { uitslag = Oefenen.vergelijk(doel: zin, gehoord: gehoord, taal: stuk.taal) }
            return
        }
        Voorlezer.shared.stop()
        fout = nil
        uitslag = nil
        do {
            try await spraak.start(taal: stuk.taal)
        } catch Spraak.Fout.geenToestemming {
            fout = String(localized: "Kniv mag de microfoon of spraakherkenning nog niet gebruiken. Zet het aan bij Instellingen › Kniv.")
        } catch Spraak.Fout.geenHerkenner {
            fout = String(localized: "Je iPhone kan deze taal (nog) niet verstaan. Luisteren en hardop meelezen kan wel.")
        } catch {
            fout = String(localized: "De microfoon starten lukte niet. Probeer het nog eens.")
        }
    }

    private func gekleurd(_ woorden: [Oefenen.Nagezegd]) -> AttributedString {
        var a = AttributedString()
        for (i, w) in woorden.enumerated() {
            var deel = AttributedString((i == 0 ? "" : " ") + w.woord)
            deel[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = w.goed ? Color.green : Color.orange
            a += deel
        }
        return a
    }

    private func oordeel(_ woorden: [Oefenen.Nagezegd]) -> LocalizedStringKey {
        let mis = woorden.filter { !$0.goed }.count
        if mis == 0 { return "Helemaal verstaan." }
        if mis * 3 <= woorden.count { return "Bijna. De oranje woorden nog eens." }
        return "Luister nog eens en probeer het rustig opnieuw."
    }
}

/// Tip als er alleen de robotstem op de iPhone staat: een betere stem kun je gratis downloaden.
struct StemTip: View {
    let taal: String

    var body: some View {
        if Voorlezer.alleenBasisStem(voor: taal) {
            Label {
                Text("Klinkt de stem als een robot? Download gratis een betere: Instellingen › Toegankelijkheid › Gesproken materiaal › Stemmen › \(Talen.naam(taal)). Kies er een met (Verbeterd) of (Premium).")
            } icon: {
                Image(systemName: "waveform")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
