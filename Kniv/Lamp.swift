import AVFoundation
import SwiftUI

/// Zaklamp, SOS, morse seinen en het scherm als lamp of bordje ("Hier!" in een drukke zaal, of een naambordje op Schiphol).
struct LampView: View {
    enum Stand: String, CaseIterable { case lamp = "Lamp", sos = "SOS", morse = "Morse", scherm = "Scherm" }
    @State private var stand: Stand = .lamp
    @State private var aan = false
    @AppStorage("lamp.niveau") private var niveau = 1.0
    @AppStorage("lamp.morse") private var bericht = "Hallo"
    @AppStorage("lamp.tempo") private var eenheid = 150.0
    @AppStorage("lamp.bordje") private var bordje = ""
    @State private var viaScherm = false
    @State private var sein: Task<Void, Never>?
    @State private var schermLicht = false
    @State private var toonScherm = false
    @State private var kleur = 0
    @State private var knipper = false

    static let kleuren: [(naam: LocalizedStringKey, kleur: Color)] = [("Wit", .white), ("Rood", .red), ("Kniv", .accentColor), ("Groen", .green)]

    var body: some View {
        VStack(spacing: 20) {
            Picker("Stand", selection: $stand) {
                ForEach(Stand.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: stand) { stop() }

            Spacer()
            switch stand {
            case .lamp: lamp
            case .sos: seinKnop(tekst: "SOS", uitleg: "Seint SOS met de lamp tot je stopt. Drie kort, drie lang, drie kort.", herhaal: true)
            case .morse: morse
            case .scherm: scherm
            }
            Spacer()
        }
        .padding(.top)
        .overlay {
            if schermLicht { Color.white.ignoresSafeArea().allowsHitTesting(false) }
        }
        .fullScreenCover(isPresented: $toonScherm) {
            SchermLamp(kleur: Self.kleuren[kleur].kleur, tekst: bordje, knipper: knipper)
        }
        .onDisappear { stop() }
    }

    private var lamp: some View {
        VStack(spacing: 28) {
            Button {
                aan.toggle()
                Zaklamp.zet(aan ? Float(niveau) : 0)
            } label: {
                Image(systemName: aan ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 64, weight: .light))
                    .frame(width: 180, height: 180)
                    .foregroundStyle(aan ? Color.white : Color.primary)
                    .background(aan ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: aan)
            .accessibilityLabel(aan ? "Lamp uit" : "Lamp aan")

            HStack {
                Image(systemName: "sun.min")
                Slider(value: $niveau, in: 0.05...1)
                    .onChange(of: niveau) { if aan { Zaklamp.zet(Float(niveau)) } }
                Image(systemName: "sun.max.fill")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
            if !Zaklamp.beschikbaar {
                Text("Deze telefoon heeft geen lamp. Gebruik Scherm.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var morse: some View {
        VStack(spacing: 18) {
            TextField("Bericht", text: $bericht)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .glas(16)
                .padding(.horizontal)
            Text(verbatim: Morse.code(bericht))
                .font(.system(.title2, design: .monospaced))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal)
            HStack {
                Image(systemName: "tortoise")
                Slider(value: $eenheid, in: 60...400).environment(\.layoutDirection, .rightToLeft)
                Image(systemName: "hare")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
            Toggle("Via het scherm", isOn: $viaScherm).padding(.horizontal, 32)
            seinKnop(tekst: bericht, uitleg: nil, herhaal: false)
        }
    }

    private var scherm: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ForEach(Self.kleuren.indices, id: \.self) { i in
                    Button { kleur = i } label: {
                        Circle().fill(Self.kleuren[i].kleur)
                            .frame(width: 48, height: 48)
                            .overlay(Circle().stroke(Color.primary.opacity(kleur == i ? 0.8 : 0.15), lineWidth: kleur == i ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.kleuren[i].naam)
                }
            }
            TextField("Tekst op het scherm (mag leeg)", text: $bordje)
                .textFieldStyle(.plain)
                .padding(14)
                .glas(16)
                .padding(.horizontal)
            Toggle("Knipperen, zodat je vrienden je vinden", isOn: $knipper).padding(.horizontal, 32)
            Text("Rood licht houdt je ogen gewend aan het donker.").font(.footnote).foregroundStyle(.secondary)
            Button { toonScherm = true } label: {
                Label("Scherm aan", systemImage: "rectangle.inset.filled").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
        }
    }

    private func seinKnop(tekst: String, uitleg: LocalizedStringKey?, herhaal: Bool) -> some View {
        VStack(spacing: 14) {
            if let uitleg { Text(uitleg).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32) }
            Button {
                sein == nil ? start(tekst, herhaal: herhaal) : stop()
            } label: {
                Label(sein == nil ? "Seinen" : "Stop", systemImage: sein == nil ? "dot.radiowaves.left.and.right" : "stop.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(Morse.code(tekst).isEmpty)
            .padding(.horizontal, 32)
        }
    }

    private func licht(_ aan: Bool) {
        if viaScherm || !Zaklamp.beschikbaar { schermLicht = aan } else { Zaklamp.zet(aan ? 1 : 0) }
    }

    private func start(_ tekst: String, herhaal: Bool) {
        let stappen = Morse.stappen(tekst)
        let ms = Int(eenheid)
        UIApplication.shared.isIdleTimerDisabled = true
        sein = Task { @MainActor in
            repeat {
                for s in stappen {
                    if Task.isCancelled { break }
                    licht(s.aan)
                    try? await Task.sleep(for: .milliseconds(ms * s.eenheden))
                }
                licht(false)
                try? await Task.sleep(for: .milliseconds(ms * 7))
            } while herhaal && !Task.isCancelled
            if !Task.isCancelled { stop() }
        }
    }

    private func stop() {
        sein?.cancel()
        sein = nil
        schermLicht = false
        aan = false
        Zaklamp.zet(0)
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

enum Zaklamp {
    static var beschikbaar: Bool { AVCaptureDevice.default(for: .video)?.hasTorch == true }

    static func zet(_ niveau: Float) {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch, (try? d.lockForConfiguration()) != nil else { return }
        if niveau <= 0 { d.torchMode = .off } else { try? d.setTorchModeOn(level: min(niveau, AVCaptureDevice.maxAvailableTorchLevel)) }
        d.unlockForConfiguration()
    }
}

/// Het hele scherm als lamp of bordje, op volle helderheid. Tik om te sluiten.
struct SchermLamp: View {
    let kleur: Color
    let tekst: String
    let knipper: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var oudeHelderheid: CGFloat = 0.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { tijd in
            let uit = knipper && Int(tijd.date.timeIntervalSinceReferenceDate / 0.4) % 2 == 1
            ZStack {
                (uit ? Color.black : kleur).ignoresSafeArea()
                if !tekst.isEmpty {
                    Text(verbatim: tekst)
                        .font(.system(size: 400, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.05)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(uit ? kleur : (kleur == .white ? Color.black : Color.white))
                        .padding()
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onTapGesture { dismiss() }
        .onAppear {
            oudeHelderheid = UIScreen.main.brightness
            UIScreen.main.brightness = 1
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIScreen.main.brightness = oudeHelderheid
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .accessibilityAction(named: "Sluiten") { dismiss() }
    }
}
