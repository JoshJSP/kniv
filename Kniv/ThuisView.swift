import SwiftData
import SwiftUI

enum Mes: String, CaseIterable, Identifiable, Hashable {
    case vastleggen, timers, splitten, kiezen

    var id: String { rawValue }
    var klaar: Bool { self == .vastleggen || self == .timers }

    var naam: LocalizedStringKey {
        switch self {
        case .vastleggen: "Vastleggen"
        case .timers: "Timers"
        case .splitten: "Splitten"
        case .kiezen: "Kiezen"
        }
    }

    var symbool: String {
        switch self {
        case .vastleggen: "square.and.pencil"
        case .timers: "timer"
        case .splitten: "divide"
        case .kiezen: "dice"
        }
    }
}

struct ThuisView: View {
    @Namespace private var ns
    @State private var pad: [Mes] = []
    @State private var uitklappend: Mes?
    @State private var toonNieuw = false
    @AppStorage("laatstGezieneVersie") private var laatstGezien = ""
    @Environment(\.accessibilityReduceMotion) private var minderBeweging
    @Query(filter: #Predicate<Notitie> { $0.bakjeNaam == nil }) private var teSorteren: [Notitie]

    private let kolommen = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack(path: $pad) {
            ScrollView {
                LazyVGrid(columns: kolommen, spacing: 14) {
                    ForEach(Mes.allCases) { mes in
                        Button { open(mes) } label: {
                            Tegel(mes: mes, uitgeklapt: uitklappend == mes, info: info(voor: mes))
                        }
                        .buttonStyle(.plain)
                        .disabled(!mes.klaar)
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
                    case .splitten, .kiezen: EmptyView()
                    }
                }
                .navigationTransition(.zoom(sourceID: mes, in: ns))
                .onAppear { uitklappend = nil }
            }
        }
        .onChange(of: AppStatus.shared.startInspreken, initial: true) { _, nu in
            if nu && pad.last != .vastleggen { pad = [.vastleggen] }
        }
        .onChange(of: AppStatus.shared.openTimers) { _, nu in
            if nu { pad = [.timers]; AppStatus.shared.openTimers = false }
        }
        .onAppear { toonNieuw = VersieInfo.huidig.map { $0.versie != laatstGezien } ?? false }
        .sheet(isPresented: $toonNieuw, onDismiss: { laatstGezien = VersieInfo.huidig?.versie ?? "" }) {
            if let info = VersieInfo.huidig { NieuwView(info: info) }
        }
    }

    private func info(voor mes: Mes) -> String? {
        if mes == .timers { return Pomodoro.shared.loopt ? (Pomodoro.shared.fase == .werk ? "Focus loopt" : "Pauze loopt") : nil }
        guard mes == .vastleggen, !teSorteren.isEmpty else { return nil }
        return teSorteren.count == 1 ? "1 te checken" : "\(teSorteren.count) te checken"
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
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(mes.klaar ? Color.accentColor : Color.secondary)
                .rotationEffect(.degrees(uitgeklapt ? -38 : 0), anchor: .bottomLeading)
            Spacer(minLength: 0)
            Text(mes.naam).font(.headline)
            Text(info ?? (mes.klaar ? " " : "Binnenkort"))
                .font(.caption)
                .foregroundStyle(info == nil ? Color.secondary : Color.accentColor)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .padding(18)
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
