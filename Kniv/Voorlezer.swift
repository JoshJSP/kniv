import AVFoundation
import Observation

/// Leest een stukje voor met de beste iPhone-stem voor die taal en houdt bij welk woord nu klinkt.
@MainActor @Observable final class Voorlezer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Voorlezer()

    private(set) var bezig = false
    private(set) var gesproken: Range<String.Index>?   // bereik in de laatst gelezen tekst

    @ObservationIgnored private let spreker = AVSpeechSynthesizer()
    @ObservationIgnored private var tekst = ""
    @ObservationIgnored private var zin: AVSpeechUtterance?   // sterk vasthouden, zodat de id niet hergebruikt wordt
    private var huidige: ObjectIdentifier? { zin.map(ObjectIdentifier.init) }

    override init() {
        super.init()
        spreker.delegate = self
    }

    /// Beste stem voor de taal: hoogste kwaliteit (premium > verbeterd > standaard), geen grapstemmen,
    /// en bij gelijke kwaliteit de standaardregio (de-DE boven de-CH).
    nonisolated static func stem(voor code: String) -> AVSpeechSynthesisVoice? {
        let regio = AVSpeechSynthesisVoice(language: code)?.language
        func score(_ s: AVSpeechSynthesisVoice) -> Int { s.quality.rawValue * 10 + (s.language == regio ? 1 : 0) }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { ($0.language == code || $0.language.hasPrefix(code + "-")) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { score($0) < score($1) }
    }

    /// Alleen de compacte (robot)stem staat erop: dan is downloaden in Instellingen de moeite waard.
    nonisolated static func alleenBasisStem(voor code: String) -> Bool {
        stem(voor: code).map { $0.quality == .default } ?? false
    }

    func lees(_ tekst: String, taal code: String, snelheid: Float = 1) {
        if spreker.isSpeaking { spreker.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let zin = AVSpeechUtterance(string: tekst)
        zin.voice = Self.stem(voor: code) ?? AVSpeechSynthesisVoice(language: code)
        zin.rate = AVSpeechUtteranceDefaultSpeechRate * snelheid
        self.tekst = tekst
        self.zin = zin
        gesproken = nil
        bezig = true
        spreker.speak(zin)
    }

    func stop() {
        spreker.stopSpeaking(at: .immediate)
        klaar(nil)
    }

    private func klaar(_ id: ObjectIdentifier?) {
        guard id == nil || id == huidige else { return }   // late melding van een vorige zin negeren
        bezig = false
        gesproken = nil
        zin = nil
        // Muziek van andere apps mag weer verder.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard id == self.huidige else { return }
            self.gesproken = Range(characterRange, in: self.tekst)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.klaar(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.klaar(id) }
    }
}
