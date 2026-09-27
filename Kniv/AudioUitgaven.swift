import AVFoundation
import Charts
import SwiftData
import SwiftUI

// MARK: Opname terugluisteren

enum Opnames {
    static var map: URL {
        let u = URL.documentsDirectory.appending(path: "spraak")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func url(_ naam: String) -> URL { map.appending(path: naam) }

    /// Bewaar de laatste opname bij de notitie, zodat je kunt terugluisteren als de tekst niet klopt.
    static func bewaar(van bron: URL) -> String? {
        guard let grootte = try? bron.resourceValues(forKeys: [.fileSizeKey]).fileSize, grootte > 2_000 else { return nil }
        let naam = UUID().uuidString + ".m4a"
        return (try? FileManager.default.copyItem(at: bron, to: url(naam))) != nil ? naam : nil
    }
}

@Observable final class Speler: NSObject, AVAudioPlayerDelegate {
    private var speler: AVAudioPlayer?
    var speelt = false

    func wissel(_ naam: String) {
        if speelt { speler?.stop(); speelt = false; return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        speler = try? AVAudioPlayer(contentsOf: Opnames.url(naam))
        speler?.delegate = self
        speelt = speler?.play() ?? false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { speelt = false }
}

struct OpnameSectie: View {
    let naam: String
    @State private var speler = Speler()

    var body: some View {
        Section {
            Button { speler.wissel(naam) } label: {
                Label(speler.speelt ? "Stop" : "Luister je opname terug", systemImage: speler.speelt ? "stop.circle.fill" : "play.circle.fill")
            }
        }
    }
}

// MARK: Uitgaven per maand uit gescande bonnen

struct UitgavenKaart: View {
    @Query private var notities: [Notitie]

    private var perMaand: [(maand: Date, bedrag: Double)] {
        let kal = Calendar.current
        let bonnen = notities.compactMap { n -> (Date, Double)? in
            guard BonParser.lijktBon(n.fotoTekst), let t = BonParser.totaal(n.fotoTekst) else { return nil }
            return (kal.date(from: kal.dateComponents([.year, .month], from: n.gemaakt))!, t)
        }
        let som = Dictionary(grouping: bonnen, by: \.0).mapValues { $0.reduce(0) { $0 + $1.1 } }
        return (0..<6).reversed().compactMap { terug in
            kal.date(byAdding: .month, value: -terug, to: kal.date(from: kal.dateComponents([.year, .month], from: Date()))!)
                .map { ($0, som[$0] ?? 0) }
        }
    }

    var body: some View {
        let data = perMaand
        if data.contains(where: { $0.bedrag > 0 }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Gescande bonnen").font(.headline)
                    Spacer()
                    Text("Deze maand \(Omzetter.euro(data.last?.bedrag ?? 0))").font(.subheadline).foregroundStyle(Color.accentColor)
                }
                Chart(data, id: \.maand) { m in
                    BarMark(x: .value("Maand", m.maand, unit: .month), y: .value("Bedrag", m.bedrag))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(4)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .frame(height: 110)
            }
            .listRowBackground(Color.clear)
        }
    }
}
