import AVFoundation
import EventKit
import LocalAuthentication
import Speech
import SwiftUI
import UserNotifications
import Vision
import VisionKit

// MARK: Spraak — op het toestel zelf uitgeschreven

@MainActor final class Spraak: ObservableObject {
    @Published var tekst = ""
    @Published var bezig = false
    private let motor = AVAudioEngine()
    private var verzoek: SFSpeechAudioBufferRecognitionRequest?
    private var taak: SFSpeechRecognitionTask?
    private var opname: AVAudioFile?
    private var zekerheid: Float = 0
    let opnamePad = FileManager.default.temporaryDirectory.appending(path: "kniv-spraak.m4a")

    enum Fout: Error { case geenToestemming, geenHerkenner }

    private var startend = false

    /// `taal`: luisteren in een andere taal dan die van de iPhone (naspreken bij Talen). Nil = taal van de iPhone.
    func start(taal: String? = nil) async throws {
        guard !startend, !bezig else { return }
        startend = true
        defer { startend = false }
        let spraakOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard spraakOK, micOK else { throw Fout.geenToestemming }
        let gekozen = taal.map { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            ?? (SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "nl-NL")))
        guard let herkenner = gekozen, herkenner.isAvailable else { throw Fout.geenHerkenner }

        let sessie = AVAudioSession.sharedInstance()
        try sessie.setCategory(.record, mode: .measurement, options: .duckOthers)
        try sessie.setActive(true, options: .notifyOthersOnDeactivation)

        let verzoek = SFSpeechAudioBufferRecognitionRequest()
        verzoek.shouldReportPartialResults = true
        verzoek.requiresOnDeviceRecognition = herkenner.supportsOnDeviceRecognition
        verzoek.addsPunctuation = true
        self.verzoek = verzoek

        let invoer = motor.inputNode
        let formaat = invoer.outputFormat(forBus: 0)
        // Tegelijk een klein m4a-bestand opnemen, voor als Whisper het beter moet verstaan.
        try? FileManager.default.removeItem(at: opnamePad)
        let opname = try? AVAudioFile(forWriting: opnamePad,
                                      settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: formaat.sampleRate,
                                                 AVNumberOfChannelsKey: formaat.channelCount, AVEncoderBitRateKey: 48_000],
                                      commonFormat: formaat.commonFormat, interleaved: formaat.isInterleaved)
        self.opname = opname
        zekerheid = 0
        invoer.removeTap(onBus: 0)       // nooit twee taps (dat crasht)
        invoer.installTap(onBus: 0, bufferSize: 1024, format: formaat) { @Sendable [verzoek, opname] buffer, _ in
            verzoek.append(buffer)
            try? opname?.write(from: buffer)
        }
        motor.prepare()
        do { try motor.start() } catch {
            invoer.removeTap(onBus: 0)
            self.opname = nil
            throw error
        }
        tekst = ""
        bezig = true
        taak = herkenner.recognitionTask(with: verzoek) { @Sendable [weak self] resultaat, _ in
            guard let resultaat else { return }
            let tekst = resultaat.bestTranscription.formattedString
            let segmenten = resultaat.bestTranscription.segments
            let zeker = segmenten.isEmpty ? 0 : segmenten.map(\.confidence).reduce(0, +) / Float(segmenten.count)
            Task { @MainActor in
                self?.tekst = tekst
                if resultaat.isFinal { self?.zekerheid = zeker }
            }
        }
    }

    /// Stopt en geeft het laatste resultaat, na een korte adempauze voor het slotwoord.
    func stop() async -> String {
        guard bezig else { return tekst }
        motor.stop()
        motor.inputNode.removeTap(onBus: 0)
        verzoek?.endAudio()
        try? await Task.sleep(for: .milliseconds(450))
        taak?.cancel()
        taak = nil
        verzoek = nil
        opname = nil      // sluit het bestand
        bezig = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return tekst
    }
}

extension Spraak {
    /// Verstond de iPhone niets, of twijfelde hij (zekerheid onder 45%)? Dan schrijft Whisper het uit via Supabase.
    /// Alleen als je bent ingelogd; maximaal 50 keer per dag.
    func verbeter() async -> String? {
        let twijfel = tekst.isEmpty || (zekerheid > 0 && zekerheid < 0.45)
        guard twijfel, let sessie = try? await KnivCloud.client.auth.session,
              let audio = try? Data(contentsOf: opnamePad), audio.count > 2_000 else { return nil }
        var url = URLComponents(string: "https://ykptlgckqppgxirtndch.supabase.co/functions/v1/spraak")!
        if let taal = Locale.current.language.languageCode?.identifier { url.queryItems = [URLQueryItem(name: "taal", value: taal)] }
        var vraag = URLRequest(url: url.url!, timeoutInterval: 20)
        vraag.httpMethod = "POST"
        vraag.setValue("Bearer \(sessie.accessToken)", forHTTPHeaderField: "Authorization")
        vraag.setValue(KnivCloud.publishable, forHTTPHeaderField: "apikey")
        vraag.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        vraag.httpBody = audio
        struct Antwoord: Decodable { let tekst: String? }
        guard let (data, antwoord) = try? await URLSession.shared.data(for: vraag),
              (antwoord as? HTTPURLResponse)?.statusCode == 200,
              let beter = try? JSONDecoder().decode(Antwoord.self, from: data).tekst, !beter.isEmpty else { return nil }
        return beter
    }
}

// MARK: Tekst uit een foto

enum TekstHerkenning {
    static func lees(_ beeld: UIImage) async -> String {
        guard let cg = beeld.cgImage else { return "" }
        let richting = CGImagePropertyOrientation(beeld.imageOrientation)
        return await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let verzoek = VNRecognizeTextRequest()
                verzoek.recognitionLevel = .accurate
                verzoek.recognitionLanguages = ["nl-NL", "en-US"]
                verzoek.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: cg, orientation: richting).perform([verzoek])
                c.resume(returning: rijen(verzoek.results ?? []).joined(separator: "\n"))
            }
        }
    }
}

/// Zet losse tekststukken die op dezelfde hoogte staan op één regel, links naar rechts.
/// Zo komt op een bon "Melk" naast "1,29" in plaats van in een aparte kolom.
func rijen(_ stukken: [VNRecognizedTextObservation]) -> [String] {
    var rijen: [(midden: CGFloat, hoogte: CGFloat, stukken: [VNRecognizedTextObservation])] = []
    for s in stukken.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
        if let i = rijen.indices.last, abs(rijen[i].midden - s.boundingBox.midY) < rijen[i].hoogte * 0.5 {
            rijen[i].stukken.append(s)
        } else {
            rijen.append((s.boundingBox.midY, s.boundingBox.height, [s]))
        }
    }
    return rijen.map { rij in
        rij.stukken.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Apple's documentcamera: vindt de randen en zet het papiertje of whiteboard vanzelf recht.
struct DocumentCamera: UIViewControllerRepresentable {
    var klaar: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(klaar: klaar) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let klaar: (UIImage?) -> Void
        init(klaar: @escaping (UIImage?) -> Void) { self.klaar = klaar }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            klaar(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { klaar(nil) }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { klaar(nil) }
    }
}

// MARK: Herinneringen op een vrij moment

enum Herinneraar {
    /// Plant een melding. Zonder tijd zoekt Kniv het eerste vrije uur (9–21) in je agenda.
    /// Met `id` (de uid van de notitie) kan Kniv de meldingen later weer intrekken, bijvoorbeeld bij de prullenbak.
    static func plan(_ titel: String, _ voorstel: Herinnering.Voorstel, id: UUID? = nil) async -> Date? {
        let centrum = UNUserNotificationCenter.current()
        guard (try? await centrum.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return nil }
        let moment = voorstel.heeftTijd ? voorstel.dag : await vrijMoment(op: voorstel.dag)
        guard moment > Date() else { return nil }       // voorbij: niet doen alsof het gelukt is

        let inhoud = UNMutableNotificationContent()
        inhoud.title = "Kniv"
        inhoud.body = titel
        inhoud.sound = .default
        inhoud.categoryIdentifier = voorstel.herhaal == nil ? MeldingActies.herinnering : MeldingActies.herhaal
        let basis = "herinnering." + (id ?? UUID()).uuidString
        let kal = Calendar.current
        var verzoeken: [UNNotificationRequest] = []
        switch voorstel.herhaal {
        case nil:
            let delen = kal.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
            verzoeken = [UNNotificationRequest(identifier: basis, content: inhoud, trigger: UNCalendarNotificationTrigger(dateMatching: delen, repeats: false))]
        case .dagelijks?, .wekelijks?:
            let velden: Set<Calendar.Component> = voorstel.herhaal == .dagelijks ? [.hour, .minute] : [.weekday, .hour, .minute]
            verzoeken = [UNNotificationRequest(identifier: basis + ".r", content: inhoud,
                                               trigger: UNCalendarNotificationTrigger(dateMatching: kal.dateComponents(velden, from: moment), repeats: true))]
        case .elke(let n)?:
            // ponytail: iOS kent geen "elke n dagen", dus de volgende 8 keer los; daarna opnieuw instellen.
            verzoeken = (0..<8).compactMap { k in
                kal.date(byAdding: .day, value: k * n, to: moment).map {
                    UNNotificationRequest(identifier: "\(basis).\(k)", content: inhoud,
                                          trigger: UNCalendarNotificationTrigger(dateMatching: kal.dateComponents([.year, .month, .day, .hour, .minute], from: $0), repeats: false))
                }
            }
        }
        for v in verzoeken { guard (try? await centrum.add(v)) != nil else { return nil } }
        return moment
    }

    /// Haalt alle geplande meldingen van deze notitie weg (ook een hele reeks).
    static func trekIn(_ id: UUID) {
        let basis = "herinnering." + id.uuidString
        let c = UNUserNotificationCenter.current()
        c.getPendingNotificationRequests { verzoeken in
            c.removePendingNotificationRequests(withIdentifiers: verzoeken.map(\.identifier).filter { $0.hasPrefix(basis) })
        }
    }

    static func vrijMoment(op dag: Date) async -> Date {
        let kal = Calendar.current
        let nu = Date()
        // Jouw gewoonte-uur op deze weekdag (geleerd van afvinken en focus), anders 9:00.
        var kandidaat = kal.date(bySettingHour: Ritme.voorkeur(voor: dag) ?? 9, minute: 0, second: 0, of: dag) ?? dag
        if kandidaat < nu {
            kandidaat = kal.nextDate(after: nu, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? nu.addingTimeInterval(3600)
        }
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true,
              let eind = kal.date(bySettingHour: 21, minute: 0, second: 0, of: dag), kandidaat < eind else { return kandidaat }
        let afspraken = store.events(matching: store.predicateForEvents(withStart: kandidaat, end: eind, calendars: nil))
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        for a in afspraken {
            if a.startDate.timeIntervalSince(kandidaat) >= 30 * 60 { break }
            if a.endDate > kandidaat { kandidaat = a.endDate }
        }
        return kandidaat
    }
}

// MARK: Face ID per bakje

enum Slot {
    static func ontgrendel(_ bakje: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open \(bakje)")) ?? false
    }
}
