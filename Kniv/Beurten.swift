import SwiftData
import SwiftUI

/// Beurten: wie is er aan de beurt voor het rondje, de afwas of de boodschappen. Meerdere roosters, lokaal bewaard.
struct Rooster: Codable, Identifiable, Equatable {
    var id = UUID()
    var naam: String
    var icoon: String
    var leden: [String] = []
    var beurt = 0
    var log: [String] = []

    var aanDeBeurt: String? { leden.isEmpty ? nil : leden[beurt % leden.count] }
}

struct BeurtenView: View {
    @AppStorage("beurten") private var opgeslagen = ""
    @AppStorage("haptiek") private var haptiek = true
    @State private var roosters: [Rooster] = []
    @State private var gekozen: UUID?
    @State private var nieuw = false
    @State private var nieuweNaam = ""

    private let iconen = ["Rondje": "wineglass", "Afwas": "sink", "Boodschappen": "cart", "Vuilnis": "trash", "Koken": "frying.pan", "Stofzuigen": "wind"]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(roosters) { r in
                            Button { gekozen = r.id } label: { Label(r.naam, systemImage: r.icoon) }
                                .buttonStyle(.bordered)
                                .tint(r.id == gekozen ? Color.accentColor : .secondary)
                        }
                        Button { nieuw = true } label: { Image(systemName: "plus") }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Nieuw rooster")
                    }
                }
                if let i = roosters.firstIndex(where: { $0.id == gekozen }) {
                    rooster($roosters[i])
                }
            }
            .padding()
        }
        .onAppear(perform: laad)
        .onChange(of: roosters) { opgeslagen = (try? String(data: JSONEncoder().encode(roosters), encoding: .utf8) ?? "") ?? "" }
        .alert("Nieuw rooster", isPresented: $nieuw) {
            TextField("Bijv. Afwas", text: $nieuweNaam)
            Button("Maak") {
                let naam = nieuweNaam.trimmingCharacters(in: .whitespaces)
                guard !naam.isEmpty else { return }
                let r = Rooster(naam: naam, icoon: iconen[naam] ?? "arrow.triangle.2.circlepath", leden: roosters.first?.leden ?? [])
                roosters.append(r)
                gekozen = r.id
                nieuweNaam = ""
            }
            Button("Annuleer", role: .cancel) {}
        }
    }

    private func rooster(_ r: Binding<Rooster>) -> some View {
        VStack(spacing: 18) {
            if let wie = r.wrappedValue.aanDeBeurt, r.wrappedValue.leden.count >= 2 {
                VStack(spacing: 8) {
                    Text("Aan de beurt").foregroundStyle(.secondary)
                    Text(wie).font(.system(size: 46, weight: .bold, design: .rounded)).foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                    HStack {
                        Button {
                            withAnimation(.snappy) {
                                let tijd = Date().formatted(date: .abbreviated, time: .shortened)
                                r.wrappedValue.log = ["\(wie) · \(tijd)"] + r.wrappedValue.log.prefix(19)
                                r.wrappedValue.beurt += 1
                            }
                        } label: { Label("Gedaan", systemImage: "checkmark").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                        Button { withAnimation(.snappy) { r.wrappedValue.beurt += 1 } } label: { Text("Sla over") }
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                }
                .padding(22)
                .glas(26)
                .sensoryFeedback(.success, trigger: r.wrappedValue.beurt) { _, _ in haptiek }
            }
            OptieEditor(opties: r.leden, placeholder: "Wie doen er mee?")
            if !r.wrappedValue.log.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Eerder").font(.headline)
                    ForEach(r.wrappedValue.log, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glas(20)
            }
            if roosters.count > 1 {
                Button("Rooster verwijderen", role: .destructive) {
                    roosters.removeAll { $0.id == r.wrappedValue.id }
                    gekozen = roosters.first?.id
                }
                .font(.footnote)
            }
        }
    }

    private func laad() {
        if let data = opgeslagen.data(using: .utf8), let r = try? JSONDecoder().decode([Rooster].self, from: data), !r.isEmpty {
            roosters = r
        } else {
            // Oude rondjes (0.18) overnemen
            let d = UserDefaults.standard
            let leden = (d.string(forKey: "rondje.leden") ?? "").split(separator: "\n").map(String.init)
            roosters = [Rooster(naam: String(localized: "Rondje"), icoon: "wineglass", leden: leden, beurt: d.integer(forKey: "rondje.beurt"),
                                log: (d.string(forKey: "rondje.log") ?? "").split(separator: "\n").map(String.init))]
        }
        gekozen = gekozen ?? roosters.first?.id
    }
}

// MARK: Eén zin per dag

enum Dagboek {
    static let bakje = "Dagboek"

    @MainActor static func bewaar(_ zin: String) {
        let ctx = KnivOpslag.container.mainContext
        if ((try? ctx.fetch(FetchDescriptor<Bakje>(predicate: #Predicate { $0.naam == "Dagboek" })))?.isEmpty ?? true) {
            ctx.insert(Bakje(naam: bakje, symbool: "book", volgorde: 50))
        }
        guard let n = Vastlegger.bewaar(zin, bron: .tekst, in: ctx) else { return }
        Vastlegger.kies(bakje, voor: n, in: ctx, leer: false)
    }
}

struct DagboekKaart: View {
    @AppStorage("dagboekAan") private var aan = true
    @AppStorage("dagboek.gevraagd") private var gevraagd = ""
    @Query(filter: #Predicate<Notitie> { $0.bakjeNaam == "Dagboek" }) private var dagboek: [Notitie]
    @State private var zin = ""

    private var tonen: Bool {
        aan && Calendar.current.component(.hour, from: Date()) >= 19 && gevraagd != MorgenBrief.vandaag
            && !dagboek.contains { Calendar.current.isDateInToday($0.gemaakt) }
    }

    var body: some View {
        if tonen {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Eén zin over vandaag?", systemImage: "book").font(.headline)
                    Spacer()
                    Button { withAnimation(.snappy) { gevraagd = MorgenBrief.vandaag } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Niet nu")
                }
                TextField("Wat bleef je bij?", text: $zin, axis: .vertical).lineLimit(1...3)
                if !zin.isEmpty {
                    Button("Bewaar in je dagboek") {
                        withAnimation(.snappy) {
                            Dagboek.bewaar(zin)
                            zin = ""
                            gevraagd = MorgenBrief.vandaag
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
