import ActivityKit
import Charts
import SwiftData
import SwiftUI
import UserNotifications

// MARK: opslag

@Model final class KnivTimer {
    var id: UUID = UUID()
    var naam: String
    var isCountdown: Bool = false
    var duur: TimeInterval = 0          // losse timer
    var eind: Date?                     // loopt tot
    var rest: TimeInterval?             // gepauzeerd met zoveel over
    var doel: Date?                     // countdown naar datum
    var werk: Int?                      // studieplan: zoveel werk tot de deadline
    var eenheid: String?
    var gemaakt: Date = Date()
    var gewijzigd: Date = Date()
    var gesynct: Date?
    var deling: String = "laptop"
    var groepID: UUID?
    var eigenaarID: UUID?

    init(naam: String, duur: TimeInterval) {
        self.naam = naam
        self.duur = duur
    }

    init(naam: String, doel: Date) {
        self.naam = naam
        self.doel = doel
        self.isCountdown = true
    }

    var loopt: Bool { eind != nil }
    func resterend(_ nu: Date) -> TimeInterval { eind.map { max(0, $0.timeIntervalSince(nu)) } ?? rest ?? duur }

    func start() {
        eind = Date().addingTimeInterval(rest ?? duur)
        rest = nil
        gewijzigd = Date()
        Meldingen.plan(id.uuidString, "\(naam) is klaar", na: resterend(Date()))
        // Op het vergrendelscherm, tenzij er een focusronde loopt (die gaat voor).
        if !Pomodoro.shared.loopt, let eind { LiveTimer.start(naam: naam, eind: eind, duur: duur) }
    }

    func pauze() {
        rest = resterend(Date())
        eind = nil
        gewijzigd = Date()
        Meldingen.annuleer(id.uuidString)
        if !Pomodoro.shared.loopt { LiveTimer.stop() }
    }

    func herstel() {
        let liep = eind != nil
        eind = nil
        rest = nil
        gewijzigd = Date()
        Meldingen.annuleer(id.uuidString)
        if liep && !Pomodoro.shared.loopt { LiveTimer.stop() }
    }
}

enum Meldingen {
    static func plan(_ id: String, _ tekst: String, na seconden: TimeInterval, categorie: String = MeldingActies.timer) {
        guard seconden > 0 else { return }
        let centrum = UNUserNotificationCenter.current()
        centrum.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            guard ok else { return }
            let inhoud = UNMutableNotificationContent()
            inhoud.title = "Kniv"
            inhoud.body = tekst
            inhoud.sound = .default
            inhoud.interruptionLevel = .timeSensitive
            inhoud.categoryIdentifier = categorie
            centrum.add(UNNotificationRequest(identifier: id, content: inhoud,
                                              trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconden, repeats: false)))
        }
    }

    static func annuleer(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

// MARK: pomodoro

@Observable final class Pomodoro {
    static let shared = Pomodoro()
    enum Fase: String { case werk, pauze }

    static let werkDuur: TimeInterval = 25 * 60
    static let pauzeDuur: TimeInterval = 5 * 60
    private static let meldingID = "kniv.pomodoro"
    private let opslag = UserDefaults.standard

    var fase: Fase
    var eind: Date?
    var rest: TimeInterval?

    private init() {
        fase = Fase(rawValue: opslag.string(forKey: "pomo.fase") ?? "") ?? .werk
        eind = opslag.object(forKey: "pomo.eind") as? Date
        rest = opslag.object(forKey: "pomo.rest") as? TimeInterval
    }

    var duur: TimeInterval { fase == .werk ? Self.werkDuur : Self.pauzeDuur }
    var loopt: Bool { eind != nil }
    var actief: Bool { eind != nil || rest != nil }

    func resterend(_ nu: Date) -> TimeInterval { eind.map { max(0, $0.timeIntervalSince(nu)) } ?? rest ?? duur }
    func fractie(_ nu: Date) -> Double { 1 - resterend(nu) / duur }

    func start() {
        eind = Date().addingTimeInterval(rest ?? duur)
        rest = nil
        Meldingen.plan(Self.meldingID, fase == .werk ? "Focus klaar. Tijd voor pauze!" : "Pauze voorbij. Nog een ronde?", na: resterend(Date()))
        LiveTimer.start(naam: fase == .werk ? "Focus" : "Pauze", eind: eind!, duur: duur)
        bewaar()
    }

    func pauze() {
        rest = resterend(Date())
        eind = nil
        Meldingen.annuleer(Self.meldingID)
        LiveTimer.stop()
        bewaar()
    }

    func stop() {
        eind = nil
        rest = nil
        fase = .werk
        Meldingen.annuleer(Self.meldingID)
        LiveTimer.stop()
        bewaar()
    }

    /// Roep aan bij elke tik: rondt een afgelopen fase af en schrijft focusminuten bij.
    func controleer(_ nu: Date = Date()) {
        guard let eind, nu >= eind else { return }
        if fase == .werk {
            Focuslog.voegToe(minuten: Int(Self.werkDuur / 60), op: eind)
            Ritme.noteer(eind.addingTimeInterval(-Self.werkDuur))
        }
        self.eind = nil
        rest = nil
        fase = fase == .werk ? .pauze : .werk
        LiveTimer.stop()
        bewaar()
    }

    private func bewaar() {
        opslag.set(fase.rawValue, forKey: "pomo.fase")
        opslag.set(eind, forKey: "pomo.eind")
        opslag.set(rest, forKey: "pomo.rest")
    }
}

enum Focuslog {
    private static let sleutel = "focuslog"

    static func dagSleutel(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func voegToe(minuten: Int, op dag: Date) {
        var log = UserDefaults.standard.dictionary(forKey: sleutel) as? [String: Int] ?? [:]
        log[dagSleutel(dag), default: 0] += minuten
        UserDefaults.standard.set(log, forKey: sleutel)
    }

    static func week(tot nu: Date = Date()) -> [(dag: Date, minuten: Int)] {
        let log = UserDefaults.standard.dictionary(forKey: sleutel) as? [String: Int] ?? [:]
        let kal = Calendar.current
        return (0..<7).reversed().compactMap { terug in
            kal.date(byAdding: .day, value: -terug, to: kal.startOfDay(for: nu)).map { ($0, log[dagSleutel($0)] ?? 0) }
        }
    }
}

// MARK: Live Activity (vergrendelscherm en Dynamic Island; de weergave zit in de widget-extensie)

enum LiveTimer {
    static func start(naam: String, eind: Date, duur: TimeInterval) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        stop()
        let staat = KnivTimerAttributes.ContentState(eind: eind, duur: duur)
        _ = try? Activity.request(attributes: KnivTimerAttributes(naam: naam), content: .init(state: staat, staleDate: eind))
    }

    static func stop() {
        for a in Activity<KnivTimerAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

// MARK: scherm

struct TimersView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \KnivTimer.gemaakt) private var timers: [KnivTimer]
    @State private var pomo = Pomodoro.shared
    @State private var nieuw: NieuwSoort?
    @State private var toonAdem = false
    @State private var toonSlaap = false
    @AppStorage("omdraaien") private var omdraaien = false
    @State private var omdraaier = Omdraaier.shared
    @AppStorage("haptiek") private var haptiek = true

    enum NieuwSoort: Identifiable { case timer, countdown; var id: Self { self } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { klok in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pomodoroKaart(klok.date)
                    extraKaart
                    lijst(titel: "Timers", timers.filter { !$0.isCountdown }, leeg: "Nog geen timers. Tik op + voor pasta, thee of de was.") {
                        TimerRij(timer: $0, nu: klok.date)
                    }
                    lijst(titel: "Countdowns", timers.filter(\.isCountdown), leeg: "Tel af naar een deadline, festival of vakantie.") {
                        CountdownRij(timer: $0, nu: klok.date)
                    }
                    focusWeek
                }
                .padding()
            }
            .onChange(of: klok.date) { _, nu in
                pomo.controleer(nu)
                for t in timers where t.loopt && t.resterend(nu) <= 0 { t.herstel() }
            }
        }
        .background(KnivAchtergrond())
        .navigationTitle("Timers")
        .toolbar {
            Menu {
                Button { nieuw = .timer } label: { Label("Timer", systemImage: "timer") }
                Button { nieuw = .countdown } label: { Label("Countdown", systemImage: "calendar") }
            } label: { Image(systemName: "plus").accessibilityLabel("Nieuw") }
        }
        .sheet(item: $nieuw) { soort in
            NieuweTimerView(countdown: soort == .countdown).presentationDetents([.medium])
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: pomo.fase) { _, _ in haptiek }
        .fullScreenCover(isPresented: $toonAdem) { AdemView() }
        .sheet(isPresented: $toonSlaap) { SlaapView() }
        .onAppear { if omdraaien { omdraaier.start() } }
        .onDisappear { omdraaier.stop() }
        .onChange(of: omdraaien) { _, aan in aan ? omdraaier.start() : omdraaier.stop() }
    }

    private var extraKaart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $omdraaien) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Omdraaien om te focussen")
                    Text(omdraaier.omlaag ? "Focus loopt. Pak je telefoon op om te pauzeren." : "Leg je telefoon met het scherm op tafel en de focus start.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Button { toonAdem = true } label: {
                Label("Even ademen", systemImage: "wind").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Divider()
            Button { toonSlaap = true } label: {
                Label("Slaapadvies", systemImage: "moon.zzz").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .glas(22)
    }

    private func pomodoroKaart(_ nu: Date) -> some View {
        VStack(spacing: 18) {
            HStack {
                Text(pomo.fase == .werk ? "Focus" : "Pauze").font(.headline)
                Spacer()
                let vandaag = Focuslog.week(tot: nu).last?.minuten ?? 0
                if vandaag > 0 { Text("Vandaag \(vandaag / 25) rondes").font(.subheadline).foregroundStyle(.secondary) }
            }
            InklapLemmet(fractie: pomo.fase == .werk ? pomo.fractie(nu) : 1 - pomo.fractie(nu))
                .frame(height: 110)
                .accessibilityHidden(true)
            Text(TimerParser.klok(pomo.resterend(nu)))
                .font(.system(size: 64, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("Nog \(Int(pomo.resterend(nu) / 60)) minuten")
            HStack(spacing: 14) {
                Button { pomo.loopt ? pomo.pauze() : pomo.start() } label: {
                    Label(pomo.loopt ? "Pauze" : (pomo.actief ? "Verder" : "Start"), systemImage: pomo.loopt ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if pomo.actief || pomo.fase == .pauze {
                    Button { pomo.stop() } label: { Image(systemName: "stop.fill").padding(.horizontal, 6) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Stop")
                }
            }
            .controlSize(.large)
        }
        .padding(20)
        .glas(26)
    }

    private func lijst<Rij: View>(titel: LocalizedStringKey, _ items: [KnivTimer], leeg: LocalizedStringKey,
                                  @ViewBuilder rij: @escaping (KnivTimer) -> Rij) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titel).font(.headline)
            if items.isEmpty {
                Text(leeg).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(items) { t in
                rij(t)
                    .padding(14)
                    .glas(18)
                    .contextMenu {
                        Button(role: .destructive) { Meldingen.annuleer(t.id.uuidString); Sync.shared.markeerVerwijderd(t); ctx.delete(t) } label: {
                            Label("Verwijder", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private var focusWeek: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus deze week").font(.headline)
            Chart(Focuslog.week(), id: \.dag) { dag in
                BarMark(x: .value("Dag", dag.dag, unit: .day), y: .value("Minuten", dag.minuten))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(5)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 130)
        }
        .padding(18)
        .glas(22)
    }
}

/// Het handvat staat stil; het lemmet klapt dicht naarmate de tijd verstrijkt.
struct InklapLemmet: View {
    var fractie: Double

    var body: some View {
        GeometryReader { geo in
            let handvat = geo.size.width * 0.42
            let lemmet = geo.size.width * 0.5
            ZStack(alignment: .leading) {
                LemmetVorm()
                    .fill(LinearGradient(colors: [Color(white: 0.93), Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
                    .overlay(LemmetVorm().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    .frame(width: lemmet, height: 34)
                    .rotationEffect(.degrees(-178 * min(max(fractie, 0), 1)), anchor: .leading)
                    .offset(x: handvat - 8)
                    .animation(.linear(duration: 1), value: fractie)
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: handvat, height: 44)
                    .overlay(alignment: .trailing) { Circle().fill(.white.opacity(0.8)).frame(width: 9).padding(.trailing, 14) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: (geo.size.width - handvat - lemmet) / 2)
        }
    }
}

struct TimerRij: View {
    let timer: KnivTimer
    let nu: Date

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.naam).font(.headline)
                Text(TimerParser.klok(timer.resterend(nu)))
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(timer.loopt ? Color.accentColor : .secondary)
                    .contentTransition(.numericText(countsDown: true))
            }
            Spacer()
            if timer.rest != nil || timer.loopt {
                Button { timer.herstel() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityLabel("Opnieuw")
            }
            Button { timer.loopt ? timer.pauze() : timer.start() } label: {
                Image(systemName: timer.loopt ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
            .accessibilityLabel(timer.loopt ? "Pauze" : "Start")
        }
    }
}

struct CountdownRij: View {
    let timer: KnivTimer
    let nu: Date

    var body: some View {
        let dagen = timer.doel.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: nu),
                                                                      to: Calendar.current.startOfDay(for: $0)).day ?? 0 } ?? 0
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.naam).font(.headline)
                if let doel = timer.doel { Text(doel, format: .dateTime.weekday(.wide).day().month()).font(.caption).foregroundStyle(.secondary) }
                if let werk = timer.werk, dagen > 0 {
                    Label("\(Studieplan.perDag(werk: werk, dagen: dagen)) \(timer.eenheid ?? "") per dag", systemImage: "books.vertical")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(dagen <= 0 ? (dagen == 0 ? "Vandaag!" : "Voorbij") : "\(dagen)")
                    .font(.system(size: dagen > 0 ? 34 : 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                if dagen > 0 { Text(dagen == 1 ? "dag" : "dagen").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NieuweTimerView: View {
    let countdown: Bool
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var naam = ""
    @State private var minuten = 10
    @State private var werk = ""
    @State private var doel = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

    private let snel: [(String, Int)] = [("Pasta", 9), ("Thee", 4), ("Eieren", 7), ("Was", 60)]

    var body: some View {
        NavigationStack {
            Form {
                TextField(countdown ? "Waar tel je naar af?" : "Naam", text: $naam)
                if countdown {
                    DatePicker("Datum", selection: $doel, in: Date()..., displayedComponents: .date)
                    TextField("Hoeveel werk? Bijv. 120 pagina's", text: $werk)
                } else {
                    Stepper("\(minuten) minuten", value: $minuten, in: 1...600)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(snel, id: \.0) { s in
                                Button("\(s.0) \(s.1)m") { naam = s.0; minuten = s.1 }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle(countdown ? "Nieuwe countdown" : "Nieuwe timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(countdown ? "Bewaar" : "Start") {
                        let t = naam.trimmingCharacters(in: .whitespaces)
                        if countdown {
                            let c = KnivTimer(naam: t.isEmpty ? "Countdown" : t, doel: doel)
                            if let w = Studieplan.werk(uit: werk) { c.werk = w.aantal; c.eenheid = w.eenheid }
                            ctx.insert(c)
                        } else {
                            let timer = KnivTimer(naam: t.isEmpty ? "Timer" : t, duur: TimeInterval(minuten * 60))
                            ctx.insert(timer)
                            timer.start()
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
