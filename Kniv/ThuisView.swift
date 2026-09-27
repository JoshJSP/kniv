import SwiftData
import SwiftUI

enum Mes: String, CaseIterable, Identifiable, Hashable {
    case vastleggen, timers, splitten, kiezen, scanner, meten

    var id: String { rawValue }
    var klaar: Bool { true }

    var naam: LocalizedStringKey {
        switch self {
        case .vastleggen: "Vastleggen"
        case .timers: "Timers"
        case .splitten: "Splitten"
        case .kiezen: "Kiezen"
        case .scanner: "Scanner"
        case .meten: "Meten"
        }
    }

    var symbool: String {
        switch self {
        case .vastleggen: "square.and.pencil"
        case .timers: "timer"
        case .splitten: "divide"
        case .kiezen: "dice"
        case .scanner: "qrcode.viewfinder"
        case .meten: "ruler"
        }
    }
}

struct ThuisView: View {
    @Namespace private var ns
    @State private var pad = NavigationPath()
    @State private var uitklappend: Mes?
    @State private var toonNieuw = false
    @State private var update: Updater.Update?
    @Environment(\.scenePhase) private var fase
    @AppStorage("laatstGezieneVersie") private var laatstGezien = ""
    @Environment(\.accessibilityReduceMotion) private var minderBeweging
    @Query(filter: #Predicate<Notitie> { $0.bakjeNaam == nil }) private var teSorteren: [Notitie]

    private let kolommen = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack(path: $pad) {
            ScrollView {
                if let update { UpdateBalk(update: update).padding([.horizontal, .top]) }
                VStack(spacing: 12) {
                    Begroeting().padding(.bottom, 4)
                    MorgenBriefKaart()
                    TerugblikKaart()
                    VandaagKaart { mes in pad = NavigationPath([mes]) }
                }
                .padding([.horizontal, .top])
                LazyVGrid(columns: kolommen, spacing: 12) {
                    ForEach(Mes.allCases) { mes in
                        Button { open(mes) } label: {
                            Tegel(mes: mes, uitgeklapt: uitklappend == mes, info: info(voor: mes))
                        }
                        .buttonStyle(.plain)
                        .disabled(!mes.klaar)
                        .contextMenu { snelleActies(mes) }
                        .matchedTransitionSource(id: mes, in: ns)
                    }
                }
                .padding()
            }
            .background(KnivAchtergrond())
            .navigationTitle("Kniv")
            .toolbar {
                NavigationLink { InstellingenView() } label: {
                    Image(systemName: "gearshape").accessibilityLabel("Instellingen")
                }
            }
            .navigationDestination(for: Mes.self) { mes in
                Group {
                    switch mes {
                    case .vastleggen: VastleggenView()
                    case .timers: TimersView()
                    case .splitten: SplittenView()
                    case .kiezen: KiezenView()
                    case .scanner: ScannerView()
                    case .meten: MetenView()
                    }
                }
                .navigationTransition(.zoom(sourceID: mes, in: ns))
                .onAppear { uitklappend = nil }
            }
        }
        .onChange(of: AppStatus.shared.startInspreken, initial: true) { _, nu in if nu { openVastleggen() } }
        .onChange(of: AppStatus.shared.actie, initial: true) { _, nu in if nu != nil { openVastleggen() } }
        .onChange(of: AppStatus.shared.openTimers) { _, nu in
            if nu { pad = NavigationPath([Mes.timers]); AppStatus.shared.openTimers = false }
        }
        .onChange(of: AppStatus.shared.openSplitten) { _, nu in
            if nu { pad = NavigationPath([Mes.splitten]); AppStatus.shared.openSplitten = false }
        }
        .onChange(of: AppStatus.shared.openKiezen) { _, nu in
            if nu { pad = NavigationPath([Mes.kiezen]); AppStatus.shared.openKiezen = false }
        }
        .onAppear { toonNieuw = VersieInfo.huidig.map { $0.versie != laatstGezien } ?? false }
        .task(id: fase) {
            guard fase == .active else { return }
            await Sync.shared.nu()
            await WeerDienst.ververs()
            let gevonden = await Updater.zoek()
            withAnimation(.snappy) { update = gevonden }
        }
        .sheet(isPresented: $toonNieuw, onDismiss: { laatstGezien = VersieInfo.huidig?.versie ?? "" }) {
            if let info = VersieInfo.huidig { NieuwView(info: info) }
        }
    }

    private func info(voor mes: Mes) -> String? {
        if mes == .vastleggen, Sync.shared.nieuwVanAnderen > 0 { return "\(Sync.shared.nieuwVanAnderen) nieuw van anderen" }
        if mes == .timers { return Pomodoro.shared.loopt ? (Pomodoro.shared.fase == .werk ? "Focus loopt" : "Pauze loopt") : nil }
        guard mes == .vastleggen, !teSorteren.isEmpty else { return nil }
        return teSorteren.count == 1 ? "1 te checken" : "\(teSorteren.count) te checken"
    }

    /// Lang indrukken op een tegel: meteen naar wat je wilt doen.
    @ViewBuilder private func snelleActies(_ mes: Mes) -> some View {
        switch mes {
        case .vastleggen:
            Button { AppStatus.shared.startInspreken = true } label: { Label("Inspreken", systemImage: "mic") }
            Button { AppStatus.shared.actie = "foto" } label: { Label("Foto maken", systemImage: "camera") }
            Button { AppStatus.shared.actie = "lijst" } label: { Label("Afvinklijstje", systemImage: "checklist") }
        case .timers:
            Button {
                if !Pomodoro.shared.loopt { Pomodoro.shared.start() }
                pad = NavigationPath([Mes.timers])
            } label: { Label("Start focus", systemImage: "timer") }
        case .kiezen:
            Button {
                AppStatus.shared.kiesTab = "Rad"
                pad = NavigationPath([Mes.kiezen])
            } label: { Label("Rad van fortuin", systemImage: "circle.dashed") }
            Button { Task { await SamenKiezen.shared.doeMee(SamenKiezen.nieuweCode()) }; pad = NavigationPath([Mes.kiezen]) } label: {
                Label("Kies samen met vrienden", systemImage: "person.2")
            }
        default:
            Button { open(mes) } label: { Label(mes.naam, systemImage: mes.symbool) }
        }
    }

    /// Opent Vastleggen vers, zodat het scherm bij verschijnen de actie (inspreken, foto…) oppakt.
    private func openVastleggen() {
        if pad.isEmpty { pad.append(Mes.vastleggen); return }
        pad = NavigationPath()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            pad.append(Mes.vastleggen)
        }
    }

    /// Het lemmet klapt kort uit de tegel, daarna zoomt het mesje open.
    private func open(_ mes: Mes) {
        guard mes.klaar else { return }
        if minderBeweging { pad.append(mes); return }
        withAnimation(.spring(duration: 0.22, bounce: 0.35)) { uitklappend = mes }
        Task {
            try? await Task.sleep(for: .milliseconds(170))
            pad.append(mes)
        }
    }
}

struct Tegel: View {
    let mes: Mes
    let uitgeklapt: Bool
    let info: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: mes.symbool)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(mes.klaar ? Color.accentColor : Color.secondary)
                .rotationEffect(.degrees(uitgeklapt ? -38 : 0), anchor: .bottomLeading)
            Spacer(minLength: 0)
            Text(mes.naam).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(info ?? (mes.klaar ? " " : "Binnenkort"))
                .font(.caption)
                .foregroundStyle(info == nil ? Color.secondary : Color.accentColor)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(14)
        .contentShape(Rectangle())
        .glas(26)
        .opacity(mes.klaar ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityHint(mes.klaar ? "Opent het mesje" : "Komt binnenkort")
    }
}

struct NieuwView: View {
    let info: VersieInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nieuw in Kniv").font(.subheadline).foregroundStyle(.secondary)
            Text(info.mesnaam).font(.largeTitle.bold())
            Text("Versie \(info.versie)").font(.footnote).foregroundStyle(.secondary)
            ForEach(info.nieuw, id: \.self) { regel in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    Text(regel)
                }
            }
            Spacer()
            Button { dismiss() } label: { Text("Top!").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(28)
        .presentationDetents([.medium, .large])
    }
}

struct IntroView: View {
    var klaar: () -> Void
    @State private var pagina = 0

    private let paginas: [(symbool: String, titel: LocalizedStringKey, uitleg: LocalizedStringKey)] = [
        ("square.grid.2x2", "Eén zakmes", "Vier handige mesjes in één app. Strak, snel en altijd bij de hand."),
        ("square.and.pencil", "Leg alles vast", "Typ, spreek in of maak een foto. Ook met de Actieknop of Siri."),
        ("sparkles", "Kniv ruimt op", "Alles belandt vanzelf in het juiste bakje. Twijfelt Kniv, dan vraagt hij het even."),
    ]

    var body: some View {
        VStack {
            TabView(selection: $pagina) {
                ForEach(paginas.indices, id: \.self) { i in
                    VStack(spacing: 22) {
                        Image(systemName: paginas[i].symbool)
                            .font(.system(size: 70, weight: .light))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.bounce, value: pagina == i)
                        Text(paginas[i].titel).font(.largeTitle.bold())
                        Text(paginas[i].uitleg)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if pagina < paginas.count - 1 { withAnimation { pagina += 1 } } else { klaar() }
            } label: {
                Text(pagina < paginas.count - 1 ? "Volgende" : "Aan de slag").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(24)
        }
        .background(KnivAchtergrond())
    }
}
