import SwiftUI

/// 's Avonds (in rustmodus) vraagt Kniv: wat moet morgen-jij weten? 's Ochtends staat het bovenaan.
enum MorgenBrief {
    static var vandaag: String { Focuslog.dagSleutel(Date()) }
    static var morgen: String { Focuslog.dagSleutel(Calendar.current.date(byAdding: .day, value: 1, to: Date())!) }
}

struct MorgenBriefKaart: View {
    @AppStorage("brief.tekst") private var tekst = ""
    @AppStorage("brief.voor") private var voor = ""          // dag waarop de brief gelezen moet worden
    @AppStorage("brief.gevraagd") private var gevraagd = ""  // dag waarop we het al vroegen
    @AppStorage("brief.gelezen") private var gelezen = ""
    @State private var concept = ""
    @FocusState private var focus: Bool

    private var ochtend: Bool { voor == MorgenBrief.vandaag && !tekst.isEmpty && gelezen != MorgenBrief.vandaag }
    private var avond: Bool {
        Rustmodus.nu() && Calendar.current.component(.hour, from: Date()) >= 18
            && gevraagd != MorgenBrief.vandaag && voor != MorgenBrief.morgen
    }

    var body: some View {
        if ochtend {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Van gisteren-jij", systemImage: "envelope.open").font(.headline)
                    Spacer()
                    Button { withAnimation(.snappy) { gelezen = MorgenBrief.vandaag } } label: { Image(systemName: "checkmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Gelezen")
                }
                Text(tekst).font(.body)
            }
            .padding(16)
            .glas(22)
            .transition(.opacity)
        } else if avond {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Wat moet morgen-jij weten?", systemImage: "moon.stars").font(.headline)
                    Spacer()
                    Button { withAnimation(.snappy) { gevraagd = MorgenBrief.vandaag } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Niet nu")
                }
                TextField("Bijvoorbeeld: laptoplader mee, om 9 uur presentatie", text: $concept, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focus)
                if !concept.isEmpty {
                    Button("Leg klaar voor morgen") {
                        withAnimation(.snappy) {
                            tekst = concept
                            voor = MorgenBrief.morgen
                            gevraagd = MorgenBrief.vandaag
                            concept = ""
                            focus = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .glas(22)
            .transition(.opacity)
        }
    }
}

/// Wat mee moet: regels of lijstjes met "mee", "meenemen" of "niet vergeten".
enum Meenemen {
    static let patroon = #"(?i)\b(mee|meenemen|meebrengen|niet vergeten|vergeet niet|bring|take)\b"#

    @MainActor static func lijst(_ notities: [Notitie]) -> [String] {
        notities.flatMap { n -> [String] in
            let kop = Herinnering.eersteMatch(patroon, in: n.tekst) != nil
            if n.isLijst && kop { return n.gesorteerdeItems.map(\.tekst) }
            return n.tekst.split(separator: "\n").map(String.init).filter { Herinnering.eersteMatch(patroon, in: $0) != nil }
        }
    }
}
