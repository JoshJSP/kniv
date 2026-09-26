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

    enum Fout: Error { case geenToestemming, geenHerkenner }

    func start() async throws {
        let spraakOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard spraakOK, micOK else { throw Fout.geenToestemming }
        guard let herkenner = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "nl-NL")),
              herkenner.isAvailable else { throw Fout.geenHerkenner }

        let sessie = AVAudioSession.sharedInstance()
        try sessie.setCategory(.record, mode: .measurement, options: .duckOthers)
        try sessie.setActive(true, options: .notifyOthersOnDeactivation)

        let verzoek = SFSpeechAudioBufferRecognitionRequest()
        verzoek.shouldReportPartialResults = true
        verzoek.requiresOnDeviceRecognition = herkenner.supportsOnDeviceRecognition
        verzoek.addsPunctuation = true
        self.verzoek = verzoek

        let invoer = motor.inputNode
        invoer.installTap(onBus: 0, bufferSize: 1024, format: invoer.outputFormat(forBus: 0)) { @Sendable [verzoek] buffer, _ in
            verzoek.append(buffer)
        }
        motor.prepare()
        try motor.start()
        tekst = ""
        bezig = true
        taak = herkenner.recognitionTask(with: verzoek) { @Sendable [weak self] resultaat, _ in
            guard let resultaat else { return }
            Task { @MainActor in self?.tekst = resultaat.bestTranscription.formattedString }
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
        bezig = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return tekst
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
                let regels = verzoek.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
                c.resume(returning: regels.joined(separator: "\n"))
            }
        }
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
    static func plan(_ titel: String, _ voorstel: Herinnering.Voorstel) async -> Date? {
        let centrum = UNUserNotificationCenter.current()
        guard (try? await centrum.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return nil }
        let moment = voorstel.heeftTijd ? voorstel.dag : await vrijMoment(op: voorstel.dag)

        let inhoud = UNMutableNotificationContent()
        inhoud.title = "Kniv"
        inhoud.body = titel
        inhoud.sound = .default
        let delen = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
        let verzoek = UNNotificationRequest(identifier: UUID().uuidString, content: inhoud,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: delen, repeats: false))
        guard (try? await centrum.add(verzoek)) != nil else { return nil }
        return moment
    }

    static func vrijMoment(op dag: Date) async -> Date {
        let kal = Calendar.current
        let nu = Date()
        var kandidaat = kal.date(bySettingHour: 9, minute: 0, second: 0, of: dag) ?? dag
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
