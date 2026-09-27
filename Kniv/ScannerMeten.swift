import ARKit
import AVFoundation
import CoreMotion
import PDFKit
import SceneKit
import SwiftData
import SwiftUI
import VisionKit

// MARK: Scanner

struct ScannerView: View {
    enum Tab: String, CaseIterable { case qr = "QR-code", document = "Document", tekst = "Tekst", maak = "Maak QR" }
    @State private var tab: Tab = .qr

    var body: some View {
        VStack(spacing: 0) {
            TabBalk(tabs: Tab.allCases, keuze: $tab) { $0.rawValue }
                .padding(.vertical, 8)
            switch tab {
            case .qr: LiveScanTab(soort: .barcode(), uitleg: "Richt op een QR-code of streepjescode")
            case .tekst: LiveScanTab(soort: .text(), uitleg: "Tik op tekst om hem te kopiëren")
            case .document: DocumentTab()
            case .maak: QRMakenView()
            }
        }
        .background(KnivAchtergrond())
        .navigationTitle("Scanner")
    }
}

struct LiveScanTab: View {
    let soort: DataScannerViewController.RecognizedDataType
    let uitleg: LocalizedStringKey
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @State private var gevonden: String?
    @State private var bewaard = false
    @AppStorage("haptiek") private var haptiek = true

    var body: some View {
        VStack(spacing: 14) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                LiveScanner(soort: soort) { tekst in
                    if tekst != gevonden { gevonden = tekst; bewaard = false }
                }
                .id(String(describing: soort))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.horizontal)
            } else {
                ContentUnavailableView("Camera niet beschikbaar", systemImage: "camera", description: Text("Geef Kniv toegang tot de camera in Instellingen."))
            }
            if let gevonden {
                VStack(alignment: .leading, spacing: 10) {
                    Text(gevonden).lineLimit(4).textSelection(.enabled)
                    HStack {
                        if let url = URL(string: gevonden), url.scheme?.hasPrefix("http") == true {
                            Button { openURL(url) } label: { Label("Open", systemImage: "safari") }.buttonStyle(.borderedProminent)
                        }
                        Button { UIPasteboard.general.string = gevonden } label: { Label("Kopieer", systemImage: "doc.on.doc") }
                            .buttonStyle(.bordered)
                        VertaalKnop(tekst: gevonden).buttonStyle(.bordered)
                        Button {
                            if let n = Vastlegger.bewaar(gevonden, bron: .foto, in: ctx) { Task { await Vastlegger.sorteer(n, in: ctx) } }
                            bewaard = true
                        } label: { Label(bewaard ? "Bewaard" : "Bewaar", systemImage: bewaard ? "checkmark" : "tray.and.arrow.down") }
                            .buttonStyle(.bordered)
                            .disabled(bewaard)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glas(20)
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text(uitleg).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom)
        .animation(.snappy, value: gevonden)
        .sensoryFeedback(.success, trigger: gevonden) { _, nu in haptiek && nu != nil }
    }
}

struct LiveScanner: UIViewControllerRepresentable {
    let soort: DataScannerViewController.RecognizedDataType
    var gevonden: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [soort], qualityLevel: .balanced, recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(gevonden: gevonden) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let gevonden: (String) -> Void
        init(gevonden: @escaping (String) -> Void) { self.gevonden = gevonden }

        static func tekst(_ item: RecognizedItem) -> String? {
            switch item {
            case .text(let t): return t.transcript
            case .barcode(let b): return b.payloadStringValue
            @unknown default: return nil
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if let t = Self.tekst(item) { gevonden(t) }
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            // Codes pakken we meteen; tekst pas als je erop tikt.
            if let eerste = addedItems.first, case .barcode = eerste, let t = Self.tekst(eerste) { gevonden(t) }
        }
    }
}

struct DocumentTab: View {
    @State private var scans: [URL] = DocumentTab.lijst()
    @State private var toonCamera = false

    static var map: URL {
        let u = URL.documentsDirectory.appending(path: "scans")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func lijst() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: map, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "pdf" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    var body: some View {
        List {
            Button { toonCamera = true } label: { Label("Scan een document", systemImage: "doc.viewfinder") }
            ForEach(scans, id: \.self) { url in
                HStack {
                    Image(systemName: "doc.richtext").foregroundStyle(Color.accentColor)
                    Text(url.deletingPathExtension().lastPathComponent)
                    Spacer()
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Deel PDF")
                }
            }
            .onDelete { i in
                i.forEach { try? FileManager.default.removeItem(at: scans[$0]) }
                scans = Self.lijst()
            }
        }
        .scrollContentBackground(.hidden)
        .fullScreenCover(isPresented: $toonCamera) {
            MeerPaginaCamera { paginas in
                toonCamera = false
                guard !paginas.isEmpty else { return }
                bewaarPDF(paginas)
                scans = Self.lijst()
            }
            .ignoresSafeArea()
        }
    }

    private func bewaarPDF(_ paginas: [UIImage]) {
        let pdf = PDFDocument()
        for (i, p) in paginas.enumerated() { if let pagina = PDFPage(image: p) { pdf.insert(pagina, at: i) } }
        let naam = "Scan " + Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        pdf.write(to: Self.map.appending(path: naam + ".pdf"))
    }
}

struct MeerPaginaCamera: UIViewControllerRepresentable {
    var klaar: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(klaar: klaar) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let klaar: ([UIImage]) -> Void
        init(klaar: @escaping ([UIImage]) -> Void) { self.klaar = klaar }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            klaar((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { klaar([]) }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { klaar([]) }
    }
}

// MARK: Meten

struct MetenView: View {
    enum Tab: String, CaseIterable { case waterpas = "Waterpas", liniaal = "Liniaal", geluid = "Geluid", terug = "Terug" }
    @State private var tab: Tab = .waterpas

    var body: some View {
        VStack(spacing: 0) {
            TabBalk(tabs: Tab.allCases, keuze: $tab) { $0.rawValue }
                .padding(.vertical, 8)
            switch tab {
            case .waterpas: WaterpasView()
            case .liniaal: LiniaalView()
            case .geluid: GeluidView()
            case .terug: TerugvindenView()
            }
        }
        .background(KnivAchtergrond())
        .navigationTitle("Meten")
    }
}

@Observable final class Houding {
    var x: Double = 0      // zwaartekracht, -1...1
    var y: Double = 0
    var z: Double = 0
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let g = data?.gravity else { return }
            self?.x = g.x
            self?.y = g.y
            self?.z = g.z
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

struct WaterpasView: View {
    @State private var houding = Houding()
    @AppStorage("haptiek") private var haptiek = true

    /// Plat op tafel: kantelen in twee richtingen. Rechtop: de hoek ten opzichte van waterpas.
    private var plat: Bool { abs(houding.z) > 0.8 }
    private var hoek: Double {
        plat ? atan2(hypot(houding.x, houding.y), abs(houding.z)) * 180 / .pi
             : atan2(houding.x, -houding.y) * 180 / .pi
    }
    private var waterpas: Bool { abs(hoek) < 0.6 }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2).frame(width: 260)
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1).frame(width: 60)
                Circle()
                    .fill(waterpas ? Color.accentColor : Color.accentColor.opacity(0.35))
                    .frame(width: 52)
                    .offset(x: plat ? houding.x * 130 : 0, y: plat ? -houding.y * 130 : 0)
                    .rotationEffect(.degrees(plat ? 0 : hoek))
                if !plat {
                    Capsule().fill(Color.accentColor.opacity(0.8)).frame(width: 240, height: 4).rotationEffect(.degrees(-hoek))
                }
            }
            .animation(.interactiveSpring, value: houding.x)
            Text("\(Omzetter.mooi(abs(hoek)))°")
                .font(.system(size: 64, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(waterpas ? Color.accentColor : .primary)
            Text(plat ? "Leg je telefoon op het oppervlak" : "Houd je telefoon tegen de rand").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Waterpas")
        .accessibilityValue(waterpas ? "Waterpas" : "\(Int(abs(hoek))) graden scheef")
        .onAppear { houding.start() }
        .onDisappear { houding.stop() }
        .sensoryFeedback(.success, trigger: waterpas) { _, nu in haptiek && nu }
    }
}

struct LiniaalView: View {
    @State private var afstand: Double?
    @State private var meting = ARMeting()

    var body: some View {
        VStack(spacing: 14) {
            if ARWorldTrackingConfiguration.isSupported {
                ZStack {
                    ARLiniaal(meting: meting)
                    Image(systemName: "plus").font(.title.weight(.light)).foregroundStyle(.white).shadow(radius: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.horizontal)
                Text(afstand.map { "\(Omzetter.mooi($0 * 100)) cm" } ?? (meting.punten == 1 ? "Richt op het eindpunt en tik op +" : "Richt het kruisje op het beginpunt"))
                    .font(afstand == nil ? .subheadline : .system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(afstand == nil ? Color.secondary : Color.accentColor)
                HStack {
                    Button { afstand = meting.zetPunt() } label: { Label("Punt", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    Button { meting.wis(); afstand = nil } label: { Image(systemName: "arrow.counterclockwise").padding(.horizontal, 6) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Opnieuw")
                }
                .controlSize(.large)
                .padding(.horizontal)
            } else {
                ContentUnavailableView("Geen AR op dit toestel", systemImage: "ruler")
            }
        }
        .padding(.bottom)
    }
}

@Observable final class ARMeting {
    let view = ARSCNView()
    private var knopen: [SCNNode] = []
    var punten = 0

    /// Plaatst een punt waar het kruisje op wijst; bij het tweede punt komt de afstand in meters terug.
    func zetPunt() -> Double? {
        if knopen.count >= 2 { wis() }
        let midden = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        guard let vraag = view.raycastQuery(from: midden, allowing: .estimatedPlane, alignment: .any),
              let raak = view.session.raycast(vraag).first else { return nil }
        let t = raak.worldTransform.columns.3
        let bol = SCNNode(geometry: SCNSphere(radius: 0.006))
        bol.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.84, green: 0.17, blue: 0.12, alpha: 1)
        bol.position = SCNVector3(t.x, t.y, t.z)
        view.scene.rootNode.addChildNode(bol)
        knopen.append(bol)
        punten = knopen.count
        guard knopen.count == 2 else { return nil }
        let a = knopen[0].position, b = knopen[1].position
        let lijn = SCNNode(geometry: SCNGeometry(sources: [SCNGeometrySource(vertices: [a, b])],
                                                 elements: [SCNGeometryElement(indices: [Int32(0), 1], primitiveType: .line)]))
        lijn.geometry?.firstMaterial?.diffuse.contents = UIColor.white
        view.scene.rootNode.addChildNode(lijn)
        knopen.append(lijn)
        return Double(SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z).lengte)
    }

    func wis() {
        knopen.forEach { $0.removeFromParentNode() }
        knopen = []
        punten = 0
    }
}

struct ARLiniaal: UIViewRepresentable {
    let meting: ARMeting

    func makeUIView(context: Context) -> ARSCNView {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        meting.view.session.run(config)
        meting.view.automaticallyUpdatesLighting = true
        return meting.view
    }

    func updateUIView(_ v: ARSCNView, context: Context) {}
    static func dismantleUIView(_ v: ARSCNView, coordinator: ()) { v.session.pause() }
}

struct GeluidView: View {
    @State private var meter = Geluidsmeter()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { _ in
            let db = meter.lees()
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 18).frame(width: 240)
                    Circle()
                        .trim(from: 0, to: min(db / 120, 1))
                        .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 240)
                        .animation(.easeOut(duration: 0.15), value: db)
                    VStack {
                        Text("\(Int(db))").font(.system(size: 64, weight: .thin, design: .rounded)).monospacedDigit()
                        Text("dB").foregroundStyle(.secondary)
                    }
                }
                Text(Geluidsmeter.omschrijving(db)).font(.title3)
                Text("Schatting via de microfoon, geen geijkte meter.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
    }
}

final class Geluidsmeter {
    private var recorder: AVAudioRecorder?

    func start() {
        Task {
            guard await AVAudioApplication.requestRecordPermission() else { return }
            try? AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try? AVAudioSession.sharedInstance().setActive(true)
            let instellingen: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1]
            recorder = try? AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"), settings: instellingen)
            recorder?.isMeteringEnabled = true
            recorder?.record()
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// dBFS (−160…0) omgerekend naar een ruwe schatting in dB(A).
    func lees() -> Double {
        guard let r = recorder else { return 0 }
        r.updateMeters()
        return min(max(Double(r.averagePower(forChannel: 0)) + 100, 0), 120)
    }

    static func omschrijving(_ db: Double) -> LocalizedStringKey {
        switch db {
        case ..<35: "Heel stil"
        case ..<55: "Rustig"
        case ..<70: "Gesprek"
        case ..<85: "Druk"
        case ..<100: "Luid, pas op je oren"
        default: "Oorverdovend"
        }
    }
}
