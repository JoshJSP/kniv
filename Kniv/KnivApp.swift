import AppIntents
import SwiftData
import SwiftUI

@main
struct KnivApp: App {
    @AppStorage("introGezien") private var introGezien = false
    @AppStorage("laatstGezieneVersie") private var laatstGezien = ""

    init() {
        // Vroeg aanmaken: iOS start Kniv op de achtergrond als je een bewaakte plek binnenloopt.
        _ = PlekWachter.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if introGezien && Sync.shared.gestart && Sync.shared.gebruiker == nil {
                    LoginView()
                } else if introGezien {
                    ThuisView()
                } else {
                    IntroView {
                        laatstGezien = VersieInfo.huidig?.versie ?? ""
                        introGezien = true
                    }
                }
            }
            .task {
                KnivOpslag.zaaiBakjes()
                KnivOpslag.herstelUIDs()
                PlekWachter.shared.start()
                await Sync.shared.start()
            }
            .modifier(MeldSchudden())
            .modifier(Rustmodus())
            .onOpenURL { url in
                switch url.host() {
                case "auth": break
                case "kies":
                    if let code = url.pathComponents.last, code != "/" {
                        Task { await SamenKiezen.shared.doeMee(code) }
                        AppStatus.shared.kiesTab = "Rad"
                        AppStatus.shared.openKiezen = true
                    }
                case "join": if let token = url.pathComponents.last, token != "/" { Task { await Sync.shared.wordLid(token) } }
                case "inspreken": AppStatus.shared.startInspreken = true
                case let actie?: AppStatus.shared.actie = actie
                case nil: break
                }
            }
        }
        .modelContainer(KnivOpslag.container)
    }
}

extension View {
    /// Liquid Glass op iOS 26, matglas op iOS 18.
    @ViewBuilder func glas(_ radius: CGFloat = 22) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

struct KnivAchtergrond: View {
    var body: some View {
        LinearGradient(colors: [Color(.systemBackground), Color.accentColor.opacity(0.07)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: Siri en de Actieknop

struct ZetInKnivIntent: AppIntent {
    static var title: LocalizedStringResource = "Zet in Kniv"
    static var description = IntentDescription("Legt tekst vast in Kniv en sorteert hem in het juiste bakje.")
    static var openAppWhenRun = false

    @Parameter(title: "Wat wil je kwijt?") var tekst: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KnivOpslag.container.mainContext
        KnivOpslag.zaaiBakjes()
        guard let n = Vastlegger.bewaar(tekst, bron: .siri, in: ctx) else { return .result(dialog: "Er stond niks in.") }
        await Vastlegger.sorteer(n, in: ctx)
        return .result(dialog: n.bakjeNaam.map { "Staat erin, bij \($0)!" } ?? "Staat erin!")
    }
}

struct InsprekenIntent: AppIntent {
    static var title: LocalizedStringResource = "Inspreken in Kniv"
    static var description = IntentDescription("Opent Kniv en begint meteen met luisteren. Handig op de Actieknop.")
    static var openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        AppStatus.shared.startInspreken = true
        return .result()
    }
}

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start focus in Kniv"
    static var description = IntentDescription("Start een focusronde van 25 minuten.")
    static var openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        if !Pomodoro.shared.loopt { Pomodoro.shared.start() }
        AppStatus.shared.openTimers = true
        return .result()
    }
}

struct KnivSnelkoppelingen: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: InsprekenIntent(),
                    phrases: ["Inspreken in \(.applicationName)", "Leg iets vast in \(.applicationName)"],
                    shortTitle: "Inspreken", systemImageName: "mic.fill")
        AppShortcut(intent: ZetInKnivIntent(),
                    phrases: ["Zet iets in \(.applicationName)", "Voeg toe aan \(.applicationName)"],
                    shortTitle: "Zet in Kniv", systemImageName: "square.and.pencil")
        AppShortcut(intent: StartFocusIntent(),
                    phrases: ["Start focus in \(.applicationName)", "Focus met \(.applicationName)"],
                    shortTitle: "Start focus", systemImageName: "timer")
        AppShortcut(intent: BewaarInKnivIntent(),
                    phrases: ["Bewaar in \(.applicationName)"],
                    shortTitle: "Bewaar in Kniv", systemImageName: "tray.and.arrow.down")
    }
}
