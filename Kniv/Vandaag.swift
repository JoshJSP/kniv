import SwiftData
import SwiftUI

/// Wat speelt er vandaag: lopende timers, herinneringen, open boodschappen en wie wie nog geld schuldig is.
/// Verschijnt alleen als er iets te melden valt.
struct VandaagKaart: View {
    var open: (Mes) -> Void
    @Query private var notities: [Notitie]
    @Query private var timers: [KnivTimer]
    @Query private var potten: [Pot]
    @State private var pomo = Pomodoro.shared

    private struct Regel: Identifiable {
        let id: String
        let icoon: String
        let tekst: String
        let mes: Mes
    }

    private func regels(_ nu: Date, vast: [Regel]) -> [Regel] {
        var r: [Regel] = []
        if pomo.actief {
            r.append(Regel(id: "pomo", icoon: "timer",
                           tekst: "\(pomo.fase == .werk ? String(localized: "Focus") : String(localized: "Pauze")) \(TimerParser.klok(pomo.resterend(nu)))",
                           mes: .timers))
        }
        for t in timers where t.loopt {
            r.append(Regel(id: "t\(t.id)", icoon: "timer", tekst: "\(t.naam) \(TimerParser.klok(t.resterend(nu)))", mes: .timers))
        }
        return r + vast
    }

    /// Alles wat niet per seconde verandert. Wordt alleen opnieuw berekend als de notities, potjes of het uur veranderen.
    private func vasteRegels(_ nu: Date) -> [Regel] {
        var r: [Regel] = []
        if let weer = WeerDienst.advies {
            r.append(Regel(id: "w", icoon: weer.contains("°") ? "thermometer.low" : "cloud.rain", tekst: weer, mes: .vastleggen))
        }
        let kal = Calendar.current
        for n in notities where !n.isVerzegeld && n.weggegooid == nil {
            if let moment = Herinnering.vind(in: n.zoekTekst, nu: n.gemaakt), kal.isDateInToday(moment.dag) {
                r.append(Regel(id: "h\(n.uid)", icoon: "bell",
                               tekst: moment.heeftTijd ? "\(moment.dag.formatted(date: .omitted, time: .shortened)) \(n.titel)" : n.titel,
                               mes: .vastleggen))
            }
        }
        for (terug, label) in [(365, String(localized: "Een jaar geleden")), (30, String(localized: "Een maand geleden"))] {
            if let dag = kal.date(byAdding: .day, value: -terug, to: nu),
               let oud = notities.first(where: { $0.bakjeNaam == "Dagboek" && kal.isDate($0.gemaakt, inSameDayAs: dag) }) {
                r.append(Regel(id: "d\(terug)", icoon: "clock.arrow.circlepath", tekst: "\(label): \(oud.titel)", mes: .vastleggen))
            }
        }
        let boodschappen = notities.filter { $0.bakjeNaam == "Boodschappen" && $0.weggegooid == nil }.reduce(0) { $0 + max($1.items.count, $1.isLijst ? 0 : 1) }
        if boodschappen > 0 {
            r.append(Regel(id: "b", icoon: "cart", tekst: String(localized: "\(boodschappen) boodschappen open"), mes: .vastleggen))
        }
        let saldo = potten.reduce(0.0) { $0 + ($1.saldi["Ik"] ?? 0) }
        if abs(saldo) >= 0.01 {
            r.append(Regel(id: "p", icoon: "eurosign.circle",
                           tekst: saldo > 0 ? String(localized: "Je krijgt nog \(Omzetter.euro(saldo))") : String(localized: "Je moet nog \(Omzetter.euro(-saldo)) betalen"),
                           mes: .splitten))
        }
        return r
    }

    var body: some View {
        let vast = vasteRegels(Date())
        let tikt = pomo.loopt || timers.contains(where: \.loopt)
        TimelineView(.periodic(from: .now, by: tikt ? 1 : 60)) { klok in
            let lijst = regels(klok.date, vast: vast)
            if !lijst.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Vandaag").font(.headline)
                    ForEach(lijst) { regel in
                        Button { open(regel.mes) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: regel.icoon).foregroundStyle(Color.accentColor).frame(width: 22)
                                Text(regel.tekst).lineLimit(1).monospacedDigit()
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .glas(22)
            }
        }
    }
}

/// Op zondag (en maandag, als je hem nog niet zag) een rustige terugblik op je week.
struct TerugblikKaart: View {
    @Query private var notities: [Notitie]
    @Query private var uitgaven: [Uitgave]
    @AppStorage("terugblikGezien") private var gezien = ""

    private var weekSleutel: String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
    }

    private var tonen: Bool {
        let dag = Calendar.current.component(.weekday, from: Date())
        return (dag == 1 || dag == 2) && gezien != weekSleutel
    }

    var body: some View {
        if tonen {
            let weekGeleden = Date().addingTimeInterval(-7 * 86_400)
            let focus = Focuslog.week().reduce(0) { $0 + $1.minuten }
            let vastgelegd = notities.filter { $0.gemaakt > weekGeleden }.count
            let uitgegeven = uitgaven.filter { $0.datum > weekGeleden }.reduce(0) { $0 + $1.bedrag }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Jouw week").font(.headline)
                    Spacer()
                    if let plaatje = deelbaar(focus: focus, vastgelegd: vastgelegd, uitgegeven: uitgegeven) {
                        ShareLink(item: plaatje, preview: SharePreview("Mijn week in Kniv", image: plaatje)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Deel je week")
                    }
                    Button { withAnimation(.snappy) { gezien = weekSleutel } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Sluiten")
                }
                HStack(spacing: 0) {
                    cijfer("\(focus / 60)u \(focus % 60)m", "gefocust")
                    cijfer("\(vastgelegd)", "vastgelegd")
                    cijfer(Omzetter.euro(uitgegeven), "in potjes")
                }
            }
            .padding(16)
            .glas(22)
            .transition(.opacity)
        }
    }

    /// De terugblik als strak kaartje voor je story.
    @MainActor private func deelbaar(focus: Int, vastgelegd: Int, uitgegeven: Double) -> Image? {
        let kaart = VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                LemmetVorm().fill(Color.white).frame(width: 60, height: 18).rotationEffect(.degrees(-30))
                Text("Mijn week in Kniv").font(.system(size: 34, weight: .bold, design: .rounded))
            }
            HStack(spacing: 0) {
                cijfer("\(focus / 60)u \(focus % 60)m", "gefocust")
                cijfer("\(vastgelegd)", "vastgelegd")
                cijfer(Omzetter.euro(uitgegeven), "in potjes")
            }
            .environment(\.colorScheme, .dark)
        }
        .foregroundStyle(.white)
        .padding(44)
        .frame(width: 1080 / 2.5, height: 1920 / 2.5)
        .background(LinearGradient(colors: [Color(red: 0.89, green: 0.2, blue: 0.16), Color(red: 0.55, green: 0.08, blue: 0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        let r = ImageRenderer(content: kaart)
        r.scale = 2.5
        return r.uiImage.map { Image(uiImage: $0) }
    }

    private func cijfer(_ waarde: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(waarde).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Color.accentColor)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
