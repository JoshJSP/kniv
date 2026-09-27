import SwiftUI
import UIKit

// MARK: Vingerkiezer: iedereen een vinger op het scherm, Kniv kiest

final class VingerVlak: UIView {
    var veranderd: ([Int: CGPoint]) -> Void = { _ in }
    private var vingers: [ObjectIdentifier: (id: Int, plek: CGPoint)] = [:]
    private var volgende = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    private func meld() { veranderd(Dictionary(uniqueKeysWithValues: vingers.values.map { ($0.id, $0.plek) })) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { vingers[ObjectIdentifier(t)] = (volgende, t.location(in: self)); volgende += 1 }
        meld()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { if let v = vingers[ObjectIdentifier(t)] { vingers[ObjectIdentifier(t)] = (v.id, t.location(in: self)) } }
        meld()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { vingers[ObjectIdentifier(t)] = nil }
        meld()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }
}

struct VingerVlakView: UIViewRepresentable {
    var veranderd: ([Int: CGPoint]) -> Void
    func makeUIView(context: Context) -> VingerVlak { let v = VingerVlak(); v.veranderd = veranderd; return v }
    func updateUIView(_ v: VingerVlak, context: Context) { v.veranderd = veranderd }
}

struct VingerkiezerView: View {
    @State private var vingers: [Int: CGPoint] = [:]
    @State private var gekozen: Int?
    @State private var aftellen: Task<Void, Never>?
    @State private var puls = false
    @AppStorage("haptiek") private var haptiek = true

    var body: some View {
        ZStack {
            Color.clear
            if vingers.isEmpty && gekozen == nil {
                VStack(spacing: 10) {
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 50)).foregroundStyle(Color.accentColor)
                    Text("Iedereen een vinger op het scherm").font(.title3.bold())
                    Text("Houd stil. Na drie tellen kiest Kniv er één.").foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)
            }
            ForEach(vingers.keys.sorted(), id: \.self) { id in
                let isGekozen = gekozen == id
                Circle()
                    .stroke(isGekozen ? Color.accentColor : Color.primary.opacity(0.6), lineWidth: isGekozen ? 10 : 5)
                    .background(Circle().fill(isGekozen ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)))
                    .frame(width: isGekozen ? 150 : 110, height: isGekozen ? 150 : 110)
                    .scaleEffect(gekozen == nil && puls ? 1.12 : 1)
                    .opacity(gekozen != nil && !isGekozen ? 0.15 : 1)
                    .position(vingers[id] ?? .zero)
                    .allowsHitTesting(false)
            }
            VingerVlakView { nieuw in
                let aantalVeranderd = nieuw.count != vingers.count
                vingers = nieuw
                if nieuw.isEmpty { gekozen = nil }
                if aantalVeranderd && gekozen == nil { begin() }
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { puls = true } }
        .animation(.spring(duration: 0.35, bounce: 0.4), value: gekozen)
        .sensoryFeedback(.impact(weight: .heavy), trigger: gekozen) { _, nu in haptiek && nu != nil }
        .accessibilityElement()
        .accessibilityLabel("Vingerkiezer. Leg allemaal een vinger op het scherm.")
    }

    /// Elke nieuwe of weggehaalde vinger zet de klok terug; bij minstens twee vingers en drie tellen stilte valt de keuze.
    private func begin() {
        aftellen?.cancel()
        guard vingers.count >= 2 else { return }
        aftellen = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, vingers.count >= 2 else { return }
            gekozen = vingers.keys.randomElement()
        }
    }
}

// MARK: Streeplijst: drankjes turven, daarna eerlijk verdelen

struct Streper: Codable, Identifiable, Equatable {
    var id = UUID()
    var naam: String
    var strepen = 0
}

struct StreeplijstView: View {
    @AppStorage("streep.lijst") private var opgeslagen = ""
    @AppStorage("streep.prijs") private var prijsTekst = "2,50"
    @AppStorage("haptiek") private var haptiek = true
    @State private var mensen: [Streper] = []
    @State private var nieuw = ""
    @State private var tik = 0

    private var prijs: Double { bedrag(prijsTekst) }
    private var totaal: Int { mensen.reduce(0) { $0 + $1.strepen } }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Prijs per streepje")
                    Spacer()
                    TextField("2,50", text: $prijsTekst).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
            }
            Section {
                ForEach($mensen) { $m in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.naam).font(.headline)
                            Text(String(repeating: "|", count: min(m.strepen, 40)) + (m.strepen > 40 ? "…" : ""))
                                .font(.system(.caption, design: .monospaced)).foregroundStyle(Color.accentColor).lineLimit(1)
                        }
                        Spacer()
                        Text(Omzetter.euro(Double(m.strepen) * prijs)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        Button { if m.strepen > 0 { m.strepen -= 1 } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("Streepje eraf bij \(m.naam)")
                        Button { m.strepen += 1; tik += 1 } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .buttonStyle(.borderless).accessibilityLabel("Streepje erbij voor \(m.naam)")
                    }
                }
                .onDelete { mensen.remove(atOffsets: $0) }
                TextField("Naam toevoegen", text: $nieuw)
                    .onSubmit {
                        let n = nieuw.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { mensen.append(Streper(naam: n)) }
                        nieuw = ""
                    }
            } footer: {
                if totaal > 0 { Text("\(totaal) streepjes · \(Omzetter.euro(Double(totaal) * prijs)) in totaal") }
            }
            if totaal > 0 {
                Section {
                    ShareLink(item: mensen.filter { $0.strepen > 0 }
                        .map { "\($0.naam): \($0.strepen)× = \(Omzetter.euro(Double($0.strepen) * prijs))" }.joined(separator: "\n")) {
                        Label("Deel de afrekening", systemImage: "square.and.arrow.up")
                    }
                    Button("Opnieuw beginnen", role: .destructive) { for i in mensen.indices { mensen[i].strepen = 0 } }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .sensoryFeedback(.impact(weight: .light), trigger: tik) { _, _ in haptiek }
        .onAppear {
            if let d = opgeslagen.data(using: .utf8), let m = try? JSONDecoder().decode([Streper].self, from: d) { mensen = m }
        }
        .onChange(of: mensen) { opgeslagen = (try? String(data: JSONEncoder().encode(mensen), encoding: .utf8) ?? "") ?? "" }
    }
}
