import AVFoundation
import CoreLocation
import CoreMotion
import SwiftUI

// MARK: Stopwatch (loopt door als Kniv dicht is: alleen de starttijd wordt bewaard)

struct StopwatchView: View {
    @AppStorage("stopwatch.start") private var start = 0.0        // 0 = staat stil
    @AppStorage("stopwatch.opgebouwd") private var opgebouwd = 0.0
    @AppStorage("stopwatch.rondes") private var rondesTekst = ""
    @Environment(\.dismiss) private var dismiss

    private var rondes: [Double] { rondesTekst.split(separator: ",").compactMap { Double($0) } }
    private func verstreken(_ nu: Date) -> Double { opgebouwd + (start > 0 ? nu.timeIntervalSinceReferenceDate - start : 0) }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.05)) { klok in
                let tijd = verstreken(klok.date)
                VStack(spacing: 28) {
                    Text(Self.tekst(tijd))
                        .font(.system(size: 64, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .padding(.top, 30)
                        .accessibilityLabel(Text(verbatim: Self.tekst(tijd)))
                    HStack(spacing: 40) {
                        Button(LocalizedStringKey(start > 0 ? "Ronde" : "Reset")) {
                            if start > 0 { rondesTekst = (rondes + [tijd]).map { String($0) }.joined(separator: ",") }
                            else { opgebouwd = 0; rondesTekst = "" }
                        }
                        .buttonStyle(RondeKnop(kleur: .secondary))
                        .disabled(start == 0 && tijd == 0)
                        Button(LocalizedStringKey(start > 0 ? "Stop" : "Start")) {
                            let nu = Date().timeIntervalSinceReferenceDate
                            if start > 0 { opgebouwd += nu - start; start = 0 } else { start = nu }
                        }
                        .buttonStyle(RondeKnop(kleur: start > 0 ? .red : .accentColor))
                    }
                    .sensoryFeedback(.impact, trigger: start)
                    List {
                        let tussen = zip(rondes, [0] + rondes).map { $0 - $1 }
                        let snelste = tussen.count > 1 ? tussen.min() : nil
                        let traagste = tussen.count > 1 ? tussen.max() : nil
                        ForEach(Array(tussen.enumerated()).reversed(), id: \.offset) { paar in
                            let (i, r) = (paar.offset, paar.element)
                            HStack {
                                Text("Ronde \(i + 1)")
                                Spacer()
                                Text(verbatim: Self.tekst(r)).monospacedDigit()
                            }
                            .foregroundStyle(r == snelste ? Color.green : r == traagste ? Color.red : Color.primary)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(KnivAchtergrond())
            .navigationTitle("Stopwatch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Klaar") { dismiss() } }
        }
    }

    static func tekst(_ s: Double) -> String {
        let cs = Int((s * 100).rounded(.down))
        let (u, m, sec, hon) = (cs / 360_000, cs / 6000 % 60, cs / 100 % 60, cs % 100)
        return u > 0 ? String(format: "%d:%02d:%02d,%02d", u, m, sec, hon) : String(format: "%02d:%02d,%02d", m, sec, hon)
    }
}

struct RondeKnop: ButtonStyle {
    let kleur: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(width: 88, height: 88)
            .foregroundStyle(kleur == .secondary ? Color.primary : Color.white)
            .background(kleur == .secondary ? AnyShapeStyle(Color.primary.opacity(0.08)) : AnyShapeStyle(kleur.gradient), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

// MARK: Hoogte (barometer)

@Observable final class Hoogtemeter {
    var relatief: Double?          // meter sinds je begon
    var absoluut: Double?          // meter boven zeeniveau (iPhone 12 en nieuwer)
    var druk: Double?              // hPa
    private let meter = CMAltimeter()

    func start() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        meter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            self?.relatief = data.relativeAltitude.doubleValue
            self?.druk = data.pressure.doubleValue * 10
        }
        if CMAltimeter.isAbsoluteAltitudeAvailable() {
            meter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, _ in
                self?.absoluut = data?.altitude
            }
        }
    }

    func stop() {
        meter.stopRelativeAltitudeUpdates()
        meter.stopAbsoluteAltitudeUpdates()
    }
}

struct HoogteView: View {
    @State private var meter = Hoogtemeter()
    @State private var nul = 0.0

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            if let r = meter.relatief {
                let stijging = r - nul
                VStack(spacing: 4) {
                    Text(verbatim: String(format: "%+.1f m", stijging))
                        .font(.system(size: 64, weight: .thin, design: .rounded)).monospacedDigit()
                    Text("sinds je begon").foregroundStyle(.secondary)
                }
                // ponytail: 3 meter per verdieping, klopt voor de meeste huizen en scholen.
                let trappen = Int((abs(stijging) / 3).rounded())
                Label(trappen == 0 ? String(localized: "Zelfde verdieping") : String(localized: "\(trappen) verdiepingen \(stijging > 0 ? String(localized: "omhoog") : String(localized: "omlaag"))"),
                      systemImage: "stairs")
                    .font(.title3)
                HStack(spacing: 12) {
                    if let a = meter.absoluut { tegel("Boven zeeniveau", String(format: "%.0f m", a)) }
                    if let d = meter.druk { tegel("Luchtdruk", String(format: "%.0f hPa", d)) }
                }
                .padding(.horizontal)
                Button("Opnieuw beginnen") { nul = r }.buttonStyle(.bordered)
            } else {
                ContentUnavailableView("Geen barometer", systemImage: "barometer", description: Text("Of Kniv mag je beweging niet lezen. Zet het aan in Instellingen."))
            }
            Spacer()
        }
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
    }

    private func tegel(_ titel: LocalizedStringKey, _ waarde: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: waarde).font(.title2.weight(.semibold)).monospacedDigit()
            Text(titel).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .glas(16)
    }
}

// MARK: Snelheid (GPS)

@Observable final class Snelheidsmeter: NSObject, CLLocationManagerDelegate {
    var kmh: Double = 0
    var hoogste: Double = 0
    var afstand: Double = 0         // meter
    var begin: Date?
    var weigert = false
    private var vorige: CLLocation?
    private let lm = CLLocationManager()

    func start() {
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.activityType = .fitness
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
    }

    func stop() { lm.stopUpdatingLocation() }

    func reset() { hoogste = 0; afstand = 0; begin = nil; vorige = nil }

    var gemiddeld: Double {
        guard let begin, Date().timeIntervalSince(begin) > 5 else { return 0 }
        return afstand / Date().timeIntervalSince(begin) * 3.6
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        weigert = m.authorizationStatus == .denied || m.authorizationStatus == .restricted
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locaties: [CLLocation]) {
        for l in locaties where l.horizontalAccuracy >= 0 && l.horizontalAccuracy < 30 {
            kmh = max(l.speed, 0) * 3.6
            hoogste = max(hoogste, kmh)
            if let v = vorige { afstand += l.distance(from: v) } else { begin = begin ?? l.timestamp }
            vorige = l
        }
    }
}

struct SnelheidView: View {
    @State private var meter = Snelheidsmeter()

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            if meter.weigert {
                ContentUnavailableView("Locatie staat uit", systemImage: "location.slash", description: Text("Zet locatie voor Kniv aan in Instellingen."))
            } else {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 18).frame(width: 240)
                    Circle()
                        .trim(from: 0, to: min(meter.kmh / 60, 1))
                        .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 240)
                        .animation(.easeOut, value: meter.kmh)
                    VStack {
                        Text(verbatim: "\(Int(meter.kmh.rounded()))").font(.system(size: 72, weight: .thin, design: .rounded)).monospacedDigit()
                        Text(verbatim: "km/h").foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    tegel("Hoogste", String(format: "%.0f km/h", meter.hoogste))
                    tegel("Gemiddeld", String(format: "%.0f km/h", meter.gemiddeld))
                    tegel("Afstand", meter.afstand < 1000 ? String(format: "%.0f m", meter.afstand) : String(format: "%.2f km", meter.afstand / 1000))
                }
                .padding(.horizontal)
                Button("Opnieuw beginnen") { meter.reset() }.buttonStyle(.bordered)
                Text("Via GPS. Werkt het best buiten, op de fiets of in de trein.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .onAppear {
            meter.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            meter.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func tegel(_ titel: LocalizedStringKey, _ waarde: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: waarde).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(titel).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .glas(16)
    }
}

// MARK: Loep: kleine lettertjes lezen, met lamp en stilzetten

struct LoepView: View {
    @State private var camera = LoepCamera()
    @State private var zoom = 2.0
    @State private var lamp = false
    @State private var stil = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LoepVoorbeeld(camera: camera)
                .ignoresSafeArea(edges: .bottom)
                .onTapGesture { stil.toggle(); camera.zetStil(stil) }
            VStack(spacing: 14) {
                if stil { Text("Stilgezet. Tik om verder te kijken.").font(.footnote).padding(8).glas(12) }
                HStack(spacing: 14) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $zoom, in: 1...camera.maxZoom)
                        .onChange(of: zoom) { camera.zoom(zoom) }
                    Image(systemName: "plus.magnifyingglass")
                    Button {
                        lamp.toggle()
                        Zaklamp.zet(lamp ? 1 : 0)
                    } label: {
                        Image(systemName: lamp ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                    .accessibilityLabel(lamp ? "Lamp uit" : "Lamp aan")
                    Button { stil.toggle(); camera.zetStil(stil) } label: {
                        Image(systemName: stil ? "play.fill" : "pause.fill")
                    }
                    .accessibilityLabel(stil ? "Verder kijken" : "Stilzetten")
                }
                .font(.title3)
                .padding(16)
                .glas(22)
            }
            .padding()
        }
        .onAppear { camera.start(zoom: zoom) }
        .onDisappear {
            camera.stop()
            if lamp { Zaklamp.zet(0) }
        }
    }
}

final class LoepCamera {
    let sessie = AVCaptureSession()
    let laag: AVCaptureVideoPreviewLayer
    private let wachtrij = DispatchQueue(label: "kniv.loep")
    private let toestel = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

    init() { laag = AVCaptureVideoPreviewLayer(session: sessie); laag.videoGravity = .resizeAspectFill }

    var maxZoom: Double { min(Double(toestel?.maxAvailableVideoZoomFactor ?? 1), 10) }

    func start(zoom z: Double) {
        wachtrij.async { [self] in
            if sessie.inputs.isEmpty, let toestel, let invoer = try? AVCaptureDeviceInput(device: toestel), sessie.canAddInput(invoer) {
                sessie.addInput(invoer)
            }
            sessie.startRunning()
            zoom(z)
        }
    }

    func stop() { wachtrij.async { [self] in sessie.stopRunning() } }

    func zoom(_ z: Double) {
        guard let toestel, (try? toestel.lockForConfiguration()) != nil else { return }
        toestel.videoZoomFactor = CGFloat(min(max(z, 1), maxZoom))
        if toestel.isFocusModeSupported(.continuousAutoFocus) { toestel.focusMode = .continuousAutoFocus }
        toestel.unlockForConfiguration()
    }

    /// Het voorbeeld bevriest op het laatste beeld zolang de verbinding uit staat.
    func zetStil(_ stil: Bool) { laag.connection?.isEnabled = !stil }
}

struct LoepVoorbeeld: UIViewRepresentable {
    let camera: LoepCamera

    final class Vlak: UIView {
        var laag: CALayer?
        override func layoutSubviews() { super.layoutSubviews(); laag?.frame = bounds }
    }

    func makeUIView(context: Context) -> Vlak {
        let v = Vlak()
        v.backgroundColor = .black
        v.layer.addSublayer(camera.laag)
        v.laag = camera.laag
        return v
    }

    func updateUIView(_ v: Vlak, context: Context) {}
}
