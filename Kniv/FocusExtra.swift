import CoreMotion
import SwiftUI

/// Telefoon met het scherm op tafel = focus. Oppakken = pauze. De nabijheidssensor zet het scherm dan uit,
/// zodat Kniv blijft opletten zonder batterij te vreten.
@Observable final class Omdraaier {
    static let shared = Omdraaier()
    private let motion = CMMotionManager()
    private var omlaagSinds: Date?
    var omlaag = false

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        UIDevice.current.isProximityMonitoringEnabled = true
        motion.deviceMotionUpdateInterval = 0.25
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let z = data?.gravity.z else { return }
            if z > 0.85 {                                   // scherm naar beneden
                if self.omlaagSinds == nil { self.omlaagSinds = Date() }
                if !self.omlaag, Date().timeIntervalSince(self.omlaagSinds!) > 1.5 {
                    self.omlaag = true
                    if !Pomodoro.shared.loopt {
                        // Neerleggen betekent focussen, ook als de vorige ronde op pauze eindigde.
                        if Pomodoro.shared.fase == .pauze && !Pomodoro.shared.actief { Pomodoro.shared.fase = .werk }
                        Pomodoro.shared.start()
                    }
                }
            } else if z < 0.3 {
                self.omlaagSinds = nil
                if self.omlaag {
                    self.omlaag = false
                    if Pomodoro.shared.loopt && Pomodoro.shared.fase == .werk { Pomodoro.shared.pauze() }
                }
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        UIDevice.current.isProximityMonitoringEnabled = false
        omlaagSinds = nil
        omlaag = false
    }
}

/// Box breathing: 4 tellen in, 4 vast, 4 uit, 4 vast. Het lemmet ademt mee, de telefoon tikt zacht bij elke wissel.
struct AdemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var minderBeweging
    @AppStorage("haptiek") private var haptiek = true
    @State private var minuten = 2
    @State private var begon: Date?

    private let fases: [(LocalizedStringKey, Double)] = [("In", 1), ("Vast", 1), ("Uit", 0), ("Vast", 0)]
    private let tel: Double = 4

    var body: some View {
        VStack(spacing: 30) {
            HStack {
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title).symbolRenderingMode(.hierarchical) }
                    .accessibilityLabel("Sluiten")
            }
            Spacer()
            TimelineView(.animation(paused: begon == nil)) { klok in
                let t = begon.map { klok.date.timeIntervalSince($0) } ?? 0
                let klaar = begon != nil && t >= Double(minuten * 60)
                let index = Int(t / tel) % 4
                let voortgang = (t.truncatingRemainder(dividingBy: tel)) / tel
                let fase = fases[index]
                let vorige = fases[(index + 3) % 4].1
                let adem = begon == nil ? 0.35 : vorige + (fase.1 - vorige) * voortgang * voortgang * (3 - 2 * voortgang)
                VStack(spacing: 28) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.08)).frame(width: 280)
                        LemmetVorm()
                            .fill(Color.accentColor.gradient)
                            .frame(width: 120 + 140 * adem, height: 36 + 42 * adem)
                            .rotationEffect(.degrees(-30))
                            .opacity(minderBeweging ? 0.4 + 0.6 * adem : 1)
                    }
                    .frame(height: 300)
                    .accessibilityHidden(true)
                    Text(klaar ? "Goed gedaan" : begon == nil ? "Adem rustig mee" : fase.0)
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.4), value: index)
                    if begon != nil && !klaar {
                        Text("\(Int(tel - t.truncatingRemainder(dividingBy: tel)))")
                            .font(.title2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: index) { if haptiek && begon != nil && !klaar { UIImpactFeedbackGenerator(style: .soft).impactOccurred() } }
                .onChange(of: klaar) { if klaar { begon = nil } }
            }
            Spacer()
            if begon == nil {
                Picker("Duur", selection: $minuten) {
                    ForEach([1, 2, 5], id: \.self) { Text("\($0) min") }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                Button { begon = Date() } label: { Text("Begin").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button("Stop") { begon = nil }.buttonStyle(.bordered)
            }
        }
        .padding(28)
        .background(KnivAchtergrond())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

/// Onder de invoerbalk: typ je een som, dan staat het antwoord er meteen.
struct RekenChip: View {
    @Binding var invoer: String

    var body: some View {
        if let uitkomst = Rekenmachine.uitkomst(invoer) {
            Button {
                invoer = "\(invoer.trimmingCharacters(in: .whitespaces)) = \(Omzetter.mooi(uitkomst))"
            } label: {
                Label("= \(Omzetter.mooi(uitkomst))", systemImage: "equal.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityHint("Zet het antwoord in je notitie")
        }
    }
}
