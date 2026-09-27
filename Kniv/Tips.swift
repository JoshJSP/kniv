import SwiftUI

/// Kniv kan veel dat je niet meteen ziet. Eén tip per dag op het startscherm, en alles op een rij in Instellingen.
enum Tips {
    static let alle: [(icoon: String, tekst: LocalizedStringKey)] = [
        ("hand.tap", "Houd een tegel ingedrukt voor snelle acties, zoals meteen inspreken of focus starten."),
        ("iphone.gen3.radiowaves.left.and.right", "Zet de Actieknop op 'Inspreken in Kniv' en leg iets vast zonder te ontgrendelen."),
        ("iphone.slash", "Leg je telefoon met het scherm op tafel en je focus start vanzelf (zet het aan bij Timers)."),
        ("mic", "Zeg tegen Siri: 'Wat staat er vandaag in Kniv?' en hoor je dag."),
        ("square.and.arrow.up", "Zet 'Bewaar in Kniv' in je deelmenu via Opdrachten en bewaar links en foto's uit elke app."),
        ("wand.and.stars", "Typ 'pasta carbonara voor 4' en tik op 'Maak er een lijstje van'. Dan heb je je boodschappen."),
        ("equal.circle", "Typ een som in de invoerbalk, zoals 12*3+4, en je ziet meteen het antwoord."),
        ("cart", "Boodschappen staan vanzelf in de volgorde van een rondje door de supermarkt."),
        ("figure.walk.departure", "Zet Thuis in Instellingen. Loop je de deur uit, dan zegt Kniv wat mee moet, en of je een paraplu nodig hebt."),
        ("moon.stars", "Zet rustmodus aan. Dan kun je 's avonds een briefje voor morgen-jij klaarleggen."),
        ("lock.shield", "Scan een bon en bewaar hem in de garantiekluis. Kniv waarschuwt voordat de garantie afloopt."),
        ("location.north", "Leg bij Meten → Terug de plek van je fiets vast. Straks wijst een pijl je de weg."),
        ("person.2", "Kies samen: start bij Kiezen een code en laat vrienden meedraaien aan hetzelfde rad."),
        ("hand.point.up.left", "Wie begint? Kiezen → Vinger: iedereen een vinger op het scherm."),
        ("wineglass", "Splitten → Strepen: turf drankjes per persoon en deel de afrekening."),
        ("hourglass", "Verzegel een notitie als tijdcapsule. Hij opent pas op de dag die jij kiest."),
        ("translate", "Scan een menukaart in het buitenland en tik op Vertaal. Dat werkt offline."),
        ("moon.zzz", "Timers → Slaapadvies: hoe laat naar bed om om 7:30 fris wakker te worden."),
    ]

    static var vanDeDag: (icoon: String, tekst: LocalizedStringKey) {
        let dag = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return alle[dag % alle.count]
    }
}

struct TipKaart: View {
    @AppStorage("tipsAan") private var aan = true
    @AppStorage("tip.weg") private var weg = ""

    var body: some View {
        if aan && weg != MorgenBrief.vandaag {
            let tip = Tips.vanDeDag
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tip.icoon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wist je dat…").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(tip.tekst).font(.subheadline)
                }
                Spacer(minLength: 0)
                Button { withAnimation(.snappy) { weg = MorgenBrief.vandaag } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Tip wegdoen")
            }
            .padding(16)
            .glas(22)
            .transition(.opacity)
        }
    }
}

struct AlleTipsView: View {
    @AppStorage("tipsAan") private var aan = true

    var body: some View {
        List {
            Section { Toggle("Dagelijkse tip op het startscherm", isOn: $aan) }
            Section { DeelmenuUitleg() }
            Section {
                ForEach(Tips.alle.indices, id: \.self) { i in
                    Label { Text(Tips.alle[i].tekst) } icon: { Image(systemName: Tips.alle[i].icoon).foregroundStyle(Color.accentColor) }
                        .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Wat Kniv kan")
    }
}
