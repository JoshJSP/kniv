import CoreMotion
import SceneKit
import SwiftUI

struct KiezenView: View {
    enum Tab: String, CaseIterable { case rad = "Rad", vinger = "Vinger", dobbelen = "Dobbelen", munt = "Munt", teams = "Teams", stemmen = "Stemmen", prikken = "Prikken" }
    @State private var tab: Tab = .rad
    @AppStorage("kiesOpties") private var optiesTekst = "Pizza\nSushi\nThai\nBurgers"

    private var opties: Binding<[String]> {
        Binding(get: { optiesTekst.split(separator: "\n").map(String.init) },
                set: { optiesTekst = $0.joined(separator: "\n") })
    }

    var body: some View {
        VStack(spacing: 0) {
            TabBalk(tabs: Tab.allCases, keuze: $tab) { $0.rawValue }
                .padding(.vertical, 8)
            if tab == .rad || tab == .stemmen { SamenBalk().padding(.bottom, 6) }
            switch tab {
            case .rad: RadView(opties: opties)
            case .vinger: VingerkiezerView()
            case .dobbelen: DobbelView()
            case .munt: MuntTab()
            case .teams: TeamsView(namen: opties)
            case .prikken: PrikkenView()
            case .stemmen:
                if SamenKiezen.shared.code != nil { SamenStemView(opties: opties) } else { StemView(opties: opties) }
            }
        }
        .background(KnivAchtergrond())
        .navigationTitle("Kiezen")
        .onAppear {
            if let lijst = AppStatus.shared.kiesOpties {
                optiesTekst = lijst.joined(separator: "\n")
                AppStatus.shared.kiesOpties = nil
                if let t = Tab(rawValue: AppStatus.shared.kiesTab) { tab = t }
            }
        }
    }
}

/// Opties bewerken: typen + Enter voegt toe, tik op een chip haalt hem weg.
struct OptieEditor: View {
    @Binding var opties: [String]
    var placeholder: LocalizedStringKey = "Optie toevoegen"
    @State private var nieuw = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(placeholder, text: $nieuw)
                .onSubmit {
                    let t = nieuw.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty && !opties.contains(t) { opties.append(t) }
                    nieuw = ""
                }
                .submitLabel(.done)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(opties, id: \.self) { o in
                        Button { opties.removeAll { $0 == o } } label: { Label(o, systemImage: "xmark").labelStyle(ChipStijl()) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("\(o), tik om te verwijderen")
                    }
                }
            }
        }
        .padding(16)
        .glas(20)
    }
}

struct ChipStijl: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.font(.caption2) }
    }
}

// MARK: rad

struct RadView: View {
    @Binding var opties: [String]
    @State private var hoek: Double = 0
    @State private var start: Double = 0
    @State private var snelheid: Double = 0
    @State private var begon: Date?
    @State private var winnaar: String?
    @State private var tik = 0
    @AppStorage("haptiek") private var haptiek = true

    private let remming: Double = 380

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TimelineView(.animation(paused: begon == nil)) { klok in
                    let h = huidigeHoek(klok.date)
                    RadSchijf(opties: opties, hoek: h, winnaar: begon == nil ? winnaar : nil)
                        .onChange(of: Rad.vak(hoek: h, aantal: opties.count)) { tik += 1 }
                        .onChange(of: klok.date) { if let begon, klok.date.timeIntervalSince(begon) >= abs(snelheid) / remming { stop(h) } }
                }
                .frame(width: 300, height: 320)
                .gesture(DragGesture(minimumDistance: 10).onEnded(zwiep))
                .accessibilityElement()
                .accessibilityLabel("Rad van fortuin")
                .accessibilityValue(winnaar ?? "")
                .accessibilityAction(named: "Draai") { draai(snelheid: Double.random(in: 900...1600)) }

                Text(winnaar ?? (begon == nil ? "Veeg om te draaien" : " "))
                    .font(winnaar == nil ? .subheadline : .largeTitle.bold())
                    .foregroundStyle(winnaar == nil ? Color.secondary : Color.accentColor)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: winnaar)

                OptieEditor(opties: $opties)
            }
            .padding()
        }
        .onChange(of: SamenKiezen.shared.worp) { _, w in volg(w) }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: tik) { _, _ in haptiek && begon != nil }
        .sensoryFeedback(.success, trigger: winnaar) { _, nu in haptiek && nu != nil }
    }

    private func huidigeHoek(_ nu: Date) -> Double {
        guard let begon else { return hoek }
        return Rad.hoek(start: start, snelheid: snelheid, remming: remming, na: nu.timeIntervalSince(begon))
    }

    /// Hoe harder je veegt, hoe langer hij draait. Richting volgt je vinger rond het midden.
    private func zwiep(_ v: DragGesture.Value) {
        let midden = CGPoint(x: 150, y: 160)
        let arm = CGVector(dx: v.startLocation.x - midden.x, dy: v.startLocation.y - midden.y)
        let richting = arm.dx * v.velocity.height - arm.dy * v.velocity.width   // kruisproduct: + = met de klok mee
        let kracht = hypot(v.velocity.width, v.velocity.height)
        guard kracht > 150 else { return }
        draai(snelheid: (richting >= 0 ? 1 : -1) * min(max(kracht * 1.1, 500), 2400))
    }

    private func draai(snelheid s: Double) {
        guard opties.count >= 2, begon == nil else { return }
        winnaar = nil
        start = hoek
        snelheid = s
        begon = Date()
        if SamenKiezen.shared.code != nil { SamenKiezen.shared.draai(opties: opties, start: hoek, snelheid: s) }
    }

    /// Iemand anders draaide: zelfde opties, beginhoek en snelheid, dus hier dezelfde uitkomst.
    private func volg(_ w: SamenKiezen.Worp?) {
        guard let w, begon == nil else { return }
        opties = w.opties
        winnaar = nil
        hoek = w.start
        start = w.start
        snelheid = w.snelheid
        begon = Date()
    }

    private func stop(_ h: Double) {
        hoek = h
        begon = nil
        winnaar = opties.isEmpty ? nil : opties[Rad.vak(hoek: h, aantal: opties.count)]
    }
}

struct RadSchijf: View {
    let opties: [String]
    let hoek: Double
    let winnaar: String?

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                ForEach(opties.indices, id: \.self) { i in
                    let stuk = 360 / Double(max(opties.count, 1))
                    Taartpunt(van: .degrees(Double(i) * stuk - 90), tot: .degrees(Double(i + 1) * stuk - 90))
                        .fill(opties[i] == winnaar ? Color.accentColor : Color(white: i.isMultiple(of: 2) ? 0.55 : 0.72).opacity(0.9))
                    Text(opties[i])
                        .font(.system(size: opties.count > 8 ? 11 : 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(width: 110, alignment: .trailing)
                        .offset(x: 58)
                        .rotationEffect(.degrees((Double(i) + 0.5) * stuk - 90))
                }
                Circle().fill(.background).frame(width: 34)
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1)
            }
            .frame(width: 290, height: 290)
            .rotationEffect(.degrees(hoek))
            .padding(.top, 22)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.accentColor)
                .shadow(radius: 2)
        }
    }
}

struct Taartpunt: Shape {
    let van: Angle
    let tot: Angle

    func path(in r: CGRect) -> Path {
        var p = Path()
        let m = CGPoint(x: r.midX, y: r.midY)
        p.move(to: m)
        p.addArc(center: m, radius: min(r.width, r.height) / 2, startAngle: van, endAngle: tot, clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: glazen dobbelstenen

struct DobbelView: View {
    @State private var tafel = Dobbeltafel()
    @State private var aantal = 2
    @State private var uitkomst: [Int] = []
    @State private var schudder = Schudder()
    @AppStorage("haptiek") private var haptiek = true

    var body: some View {
        VStack(spacing: 14) {
            DobbelScene(tafel: tafel)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .glas(26)
                .padding(.horizontal)
                .onTapGesture { gooi() }
                .accessibilityElement()
                .accessibilityLabel("Dobbelstenen")
                .accessibilityValue(uitkomst.isEmpty ? "Nog niet gegooid" : uitkomst.map(String.init).joined(separator: ", "))
                .accessibilityAction(named: "Gooi") { gooi() }
            Text(uitkomst.isEmpty ? "Schud of tik om te gooien" : uitkomst.count > 1 ? "\(uitkomst.map(String.init).joined(separator: " + ")) = \(uitkomst.reduce(0, +))" : "\(uitkomst[0])")
                .font(uitkomst.isEmpty ? .subheadline : .title.bold())
                .foregroundStyle(uitkomst.isEmpty ? Color.secondary : Color.accentColor)
            Stepper("\(aantal) \(aantal == 1 ? "steen" : "stenen")", value: $aantal, in: 1...6)
                .padding(.horizontal, 24)
                .onChange(of: aantal) { tafel.zet(aantal) }
            Spacer()
        }
        .padding(.top, 8)
        .onAppear {
            tafel.zet(aantal)
            AppStatus.shared.inDobbelmesje = true
            schudder.start { gooi() }
        }
        .onDisappear {
            AppStatus.shared.inDobbelmesje = false
            schudder.stop()
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: uitkomst) { _, _ in haptiek }
    }

    private func gooi() {
        uitkomst = []
        Task { uitkomst = await tafel.gooi() }
    }
}

/// Merkt schudden via de versnellingsmeter.
final class Schudder {
    private let motion = CMMotionManager()
    private var laatste = Date.distantPast

    func start(_ actie: @escaping () -> Void) {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.userAcceleration else { return }
            if sqrt(a.x * a.x + a.y * a.y + a.z * a.z) > 1.8, Date().timeIntervalSince(self.laatste) > 1.2 {
                self.laatste = Date()
                actie()
            }
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

final class Dobbeltafel {
    let scene = SCNScene()
    private var stenen: [SCNNode] = []
    // Volgorde van SCNBox-vlakken: voor, rechts, achter, links, boven, onder. Tegenover elkaar telt op tot 7.
    private let waarden = [1, 2, 6, 5, 3, 4]
    private lazy var materialen: [SCNMaterial] = waarden.map(Dobbeltafel.vlak)

    init() {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 42
        camera.position = SCNVector3(0, 9, 5.5)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)

        let licht = SCNNode()
        licht.light = SCNLight()
        licht.light?.type = .directional
        licht.light?.castsShadow = true
        licht.light?.shadowColor = UIColor.black.withAlphaComponent(0.25)
        licht.eulerAngles = SCNVector3(-Float.pi / 2.6, Float.pi / 6, 0)
        scene.rootNode.addChildNode(licht)
        let omgeving = SCNNode()
        omgeving.light = SCNLight()
        omgeving.light?.type = .ambient
        omgeving.light?.intensity = 500
        scene.rootNode.addChildNode(omgeving)

        let vloer = SCNNode(geometry: SCNFloor())
        vloer.geometry?.firstMaterial?.colorBufferWriteMask = []   // onzichtbaar, maar vangt schaduw en stenen
        vloer.physicsBody = .static()
        scene.rootNode.addChildNode(vloer)
        for (x, z, ry) in [(0.0, -4.2, 0.0), (0.0, 4.2, 0.0), (-3.2, 0.0, Double.pi / 2), (3.2, 0.0, Double.pi / 2)] {
            let muur = SCNNode(geometry: SCNBox(width: 10, height: 6, length: 0.2, chamferRadius: 0))
            muur.opacity = 0
            muur.position = SCNVector3(x, 3, z)
            muur.eulerAngles.y = Float(ry)
            muur.physicsBody = .static()
            scene.rootNode.addChildNode(muur)
        }
        scene.physicsWorld.gravity = SCNVector3(0, -25, 0)
    }

    func zet(_ aantal: Int) {
        stenen.forEach { $0.removeFromParentNode() }
        stenen = (0..<aantal).map { i in
            let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.16)
            box.materials = materialen
            let steen = SCNNode(geometry: box)
            steen.position = SCNVector3(Float(i % 3) * 1.4 - 1.4, 0.6, Float(i / 3) * 1.4 - 0.7)
            let lichaam = SCNPhysicsBody.dynamic()
            lichaam.mass = 0.2
            lichaam.restitution = 0.35
            lichaam.friction = 0.6
            lichaam.rollingFriction = 0.1
            steen.physicsBody = lichaam
            scene.rootNode.addChildNode(steen)
            return steen
        }
    }

    /// Gooit alle stenen en wacht tot ze stil liggen; geeft de ogen die boven liggen.
    @MainActor func gooi() async -> [Int] {
        for (i, s) in stenen.enumerated() {
            s.physicsBody?.velocity = SCNVector3Zero
            s.position = SCNVector3(Float(i) * 0.5 - 1, 3 + Float(i) * 0.3, 2.5)
            s.physicsBody?.resetTransform()
            s.physicsBody?.applyForce(SCNVector3(Float.random(in: -2...2), 1.5, Float.random(in: -9 ... -6)), asImpulse: true)
            s.physicsBody?.applyTorque(SCNVector4(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: 2...5)), asImpulse: true)
        }
        try? await Task.sleep(for: .milliseconds(500))
        for _ in 0..<40 {
            let stil = stenen.allSatisfy {
                guard let b = $0.physicsBody else { return true }
                return b.velocity.lengte < 0.05 && SCNVector3(b.angularVelocity.x, b.angularVelocity.y, b.angularVelocity.z).lengte * abs(b.angularVelocity.w) < 0.05
            }
            if stil { break }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return stenen.map(bovenkant)
    }

    private func bovenkant(_ steen: SCNNode) -> Int {
        let normalen = [SCNVector3(0, 0, 1), SCNVector3(1, 0, 0), SCNVector3(0, 0, -1), SCNVector3(-1, 0, 0), SCNVector3(0, 1, 0), SCNVector3(0, -1, 0)]
        let omhoog = normalen.map { steen.presentation.convertVector($0, to: nil).y }
        return waarden[omhoog.indices.max { omhoog[$0] < omhoog[$1] } ?? 4]
    }

    /// Een glazen vlak met ogen erop.
    private static func vlak(_ ogen: Int) -> SCNMaterial {
        let maat: CGFloat = 256
        let beeld = UIGraphicsImageRenderer(size: CGSize(width: maat, height: maat)).image { ctx in
            UIColor(white: 1, alpha: 0.22).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: maat, height: maat))
            let plekken: [Int: [(CGFloat, CGFloat)]] = [
                1: [(0.5, 0.5)], 2: [(0.27, 0.27), (0.73, 0.73)], 3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
                4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
                5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
                6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)],
            ]
            let kleur = ogen == 1 ? UIColor(red: 0.84, green: 0.17, blue: 0.12, alpha: 1) : UIColor(white: 0.08, alpha: 0.9)
            kleur.setFill()
            for (x, y) in plekken[ogen] ?? [] {
                ctx.cgContext.fillEllipse(in: CGRect(x: x * maat - 22, y: y * maat - 22, width: 44, height: 44))
            }
        }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = beeld
        m.metalness.contents = 0.0
        m.roughness.contents = 0.08
        m.transparency = 0.92
        m.isDoubleSided = false
        m.blendMode = .alpha
        return m
    }
}

extension SCNVector3 {
    var lengte: Float { sqrt(x * x + y * y + z * z) }
}

struct DobbelScene: UIViewRepresentable {
    let tafel: Dobbeltafel

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = tafel.scene
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.isPlaying = true
        v.autoenablesDefaultLighting = false
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {}
}

// MARK: munt

struct MuntTab: View {
    @State private var hoek: Double = 0
    @State private var uitslag: String?
    @AppStorage("haptiek") private var haptiek = true

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            MuntView(hoek: hoek)
                .frame(width: 200, height: 200)
                .onTapGesture(perform: gooi)
                .accessibilityElement()
                .accessibilityLabel("Munt")
                .accessibilityValue(uitslag ?? "")
                .accessibilityAction(named: "Gooi", gooi)
            Text(uitslag ?? "Tik om op te gooien")
                .font(uitslag == nil ? .subheadline : .largeTitle.bold())
                .foregroundStyle(uitslag == nil ? Color.secondary : Color.accentColor)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .medium), trigger: uitslag) { _, nu in haptiek && nu != nil }
    }

    private func gooi() {
        uitslag = nil
        let halveDraaien = Double(Int.random(in: 9...14))
        withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 1.5)) { hoek += 180 * halveDraaien } completion: {
            uitslag = Int((hoek / 180).rounded()).isMultiple(of: 2) ? String(localized: "Kop") : String(localized: "Munt")
        }
    }
}

/// Een munt die om zijn as draait; zodra de achterkant naar je toe staat zie je "munt".
struct MuntView: View, Animatable {
    var hoek: Double
    var animatableData: Double {
        get { hoek }
        set { hoek = newValue }
    }

    var body: some View {
        let rest = hoek.truncatingRemainder(dividingBy: 360)
        let voorkant = rest < 90 || rest > 270
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.95, green: 0.82, blue: 0.45), Color(red: 0.75, green: 0.58, blue: 0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(Color(red: 0.6, green: 0.45, blue: 0.15), lineWidth: 6).padding(8)
            Group {
                if voorkant {
                    Image(systemName: "crown.fill").font(.system(size: 64))
                } else {
                    Text("1").font(.system(size: 90, weight: .bold, design: .serif))
                }
            }
            .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.12))
            .scaleEffect(x: 1, y: voorkant ? 1 : -1)
        }
        .rotation3DEffect(.degrees(hoek), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
    }
}

// MARK: teams

struct TeamsView: View {
    @Binding var namen: [String]
    @State private var aantal = 2
    @State private var teams: [[String]] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                OptieEditor(opties: $namen, placeholder: "Naam toevoegen")
                Stepper("\(aantal) teams", value: $aantal, in: 2...max(2, namen.count))
                    .padding(.horizontal, 6)
                Button {
                    var rng = SystemRandomNumberGenerator()
                    withAnimation(.spring(duration: 0.45, bounce: 0.3)) { teams = Teams.verdeel(namen, in: aantal, rng: &rng) }
                } label: { Label("Verdeel", systemImage: "shuffle").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(namen.count < 2)
                ForEach(teams.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Team \(i + 1)").font(.headline).foregroundStyle(Color.accentColor)
                        ForEach(teams[i], id: \.self) { Text($0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glas(20)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding()
        }
    }
}

// MARK: veegstemmen (op één telefoon doorgeven, tot delen via de cloud er is)

struct StemView: View {
    @Binding var opties: [String]
    @State private var stemmers = ""
    @State private var stemmen: [String: Set<String>] = [:]
    @State private var beurt: String?
    @State private var index = 0
    @State private var sleep: CGSize = .zero
    @State private var klaar = false
    @AppStorage("haptiek") private var haptiek = true

    private var namen: [String] {
        stemmers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if klaar {
                    uitslag
                } else if let beurt {
                    Text("\(beurt) stemt").font(.headline)
                    if index < opties.count { kaart(opties[index]) }
                    Text("Rechts = ja, links = nee").font(.caption).foregroundStyle(.secondary)
                } else {
                    OptieEditor(opties: $opties)
                    TextField("Wie stemmen er? (komma's)", text: $stemmers)
                        .padding(16)
                        .glas(20)
                    Button { stemmen = [:]; volgende() } label: { Label("Start stemming", systemImage: "hand.thumbsup").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(opties.count < 2 || namen.isEmpty)
                }
            }
            .padding()
        }
        .sensoryFeedback(.selection, trigger: index) { _, _ in haptiek }
    }

    private func kaart(_ optie: String) -> some View {
        Text(optie)
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .glas(30)
            .overlay(alignment: .topLeading) {
                Text("JA").font(.title.bold()).foregroundStyle(.green).padding(24).opacity(Double(max(0, sleep.width / 100)))
            }
            .overlay(alignment: .topTrailing) {
                Text("NEE").font(.title.bold()).foregroundStyle(Color.accentColor).padding(24).opacity(Double(max(0, -sleep.width / 100)))
            }
            .offset(x: sleep.width, y: sleep.height * 0.2)
            .rotationEffect(.degrees(sleep.width / 18))
            .gesture(DragGesture()
                .onChanged { sleep = $0.translation }
                .onEnded { v in
                    if abs(v.translation.width) > 110 { stem(ja: v.translation.width > 0) } else { withAnimation(.spring) { sleep = .zero } }
                })
            .id(index)
            .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
            .accessibilityElement()
            .accessibilityLabel(optie)
            .accessibilityAction(named: "Ja") { stem(ja: true) }
            .accessibilityAction(named: "Nee") { stem(ja: false) }
    }

    private func stem(ja: Bool) {
        guard let beurt else { return }
        if ja { stemmen[beurt, default: []].insert(opties[index]) } else { stemmen[beurt, default: []].remove(opties[index]) }
        withAnimation(.snappy) {
            sleep = .zero
            index += 1
            if index >= opties.count { volgende() }
        }
    }

    private func volgende() {
        let gedaan = Set(stemmen.keys)
        if let volgende = namen.first(where: { !gedaan.contains($0) }) {
            stemmen[volgende] = stemmen[volgende] ?? []
            beurt = volgende
            index = 0
        } else {
            beurt = nil
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { klaar = true }
        }
    }

    private var uitslag: some View {
        let winnaars = Stemming.winnaars(stemmen, opties: opties)
        return VStack(spacing: 14) {
            Text("En de winnaar is…").foregroundStyle(.secondary)
            Text(winnaars.isEmpty ? "Niemand wilde iets 🙃" : winnaars.joined(separator: " & "))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .multilineTextAlignment(.center)
            ForEach(opties.sorted { Stemming.ja($0, stemmen) > Stemming.ja($1, stemmen) }, id: \.self) { o in
                HStack { Text(o); Spacer(); Text("\(Stemming.ja(o, stemmen)) × ja").foregroundStyle(.secondary) }
            }
            .padding(.horizontal)
            Button("Nieuwe stemming") { klaar = false; stemmen = [:] }.buttonStyle(.bordered)
        }
        .padding(20)
        .glas(26)
    }
}
