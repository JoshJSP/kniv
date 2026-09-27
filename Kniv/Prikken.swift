import SwiftData
import SwiftUI

/// Prikken: "wanneer kan iedereen?". Een prik heeft een paar data; ieder zet een stem (welke data wel).
/// Beide zijn records (soort "prik" en "prikstem") in dezelfde gedeelde groep, dus het werkt als een gedeeld lijstje.
@Model final class Prik {
    var uid: UUID = UUID()
    var titel: String = ""
    var opties: [Date] = []
    var gemaakt: Date = Date()
    var gewijzigd: Date = Date()
    var gesynct: Date?
    var deling: String = "laptop"
    var groepID: UUID?
    var eigenaarID: UUID?

    init(titel: String, opties: [Date]) {
        self.titel = titel
        self.opties = opties.sorted()
    }
}

@Model final class PrikStem {
    var uid: UUID = UUID()
    var prikUID: UUID?
    var naam: String = ""
    var wie: UUID?
    var ja: [Date] = []
    var gewijzigd: Date = Date()
    var gesynct: Date?
    var deling: String = "laptop"
    var groepID: UUID?
    var eigenaarID: UUID?

    init() {}
}

extension Prik: Synchroon {
    static var soort: String { "prik" }
    static func nieuw() -> Prik { Prik(titel: "", opties: []) }
    var syncID: UUID { get { uid } set { uid = newValue } }
    func rijData() -> RijData { RijData(gemaakt: gemaakt, naam: titel, opties: opties) }
    func pasToe(_ d: RijData, in ctx: ModelContext) {
        titel = d.naam ?? titel
        opties = (d.opties ?? opties).sorted()
        if let g = d.gemaakt { gemaakt = g }
    }
}

extension PrikStem: Synchroon {
    static var soort: String { "prikstem" }
    static func nieuw() -> PrikStem { PrikStem() }
    var syncID: UUID { get { uid } set { uid = newValue } }
    func rijData() -> RijData { RijData(naam: naam, prik: prikUID, ja: ja, wie: wie) }
    func pasToe(_ d: RijData, in ctx: ModelContext) {
        naam = d.naam ?? naam
        prikUID = d.prik
        ja = d.ja ?? []
        wie = d.wie
    }
}

// MARK: schermen

struct PrikkenView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Prik.gemaakt, order: .reverse) private var prikken: [Prik]
    @State private var nieuw = false

    var body: some View {
        List {
            if prikken.isEmpty {
                ContentUnavailableView("Wanneer kan iedereen?", systemImage: "calendar.badge.clock",
                                       description: Text("Kies een paar data, deel de link, en zie welke dag het beste uitkomt."))
                    .listRowBackground(Color.clear)
            }
            ForEach(prikken) { p in
                NavigationLink { PrikView(prik: p) } label: {
                    VStack(alignment: .leading) {
                        Text(p.titel).font(.headline)
                        Text("\(p.opties.count) data\(p.groepID != nil ? " · gedeeld" : "")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { for i in $0 { Sync.shared.markeerVerwijderd(prikken[i]); ctx.delete(prikken[i]) } }
            Button { nieuw = true } label: { Label("Nieuwe prik", systemImage: "plus") }
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $nieuw) { NieuwePrikView() }
    }
}

struct NieuwePrikView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var titel = ""
    @State private var datum = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!.addingTimeInterval(19 * 3600)
    @State private var opties: [Date] = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("Waarvoor? Bijv. Etentje met de groep", text: $titel)
                Section("Opties") {
                    DatePicker("Datum en tijd", selection: $datum, in: Date()...)
                    Button { if !opties.contains(datum) { opties.append(datum); opties.sort() } } label: { Label("Voeg toe", systemImage: "plus.circle") }
                    ForEach(opties, id: \.self) { d in Text(d, format: .dateTime.weekday(.wide).day().month().hour().minute()) }
                        .onDelete { opties.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("Nieuwe prik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Maak") {
                        ctx.insert(Prik(titel: titel.isEmpty ? String(localized: "Afspraak") : titel, opties: opties))
                        dismiss()
                    }
                    .disabled(opties.count < 2)
                }
            }
        }
    }
}

struct PrikView: View {
    @Bindable var prik: Prik
    @Environment(\.modelContext) private var ctx
    @Query private var alleStemmen: [PrikStem]
    @State private var deelToken: String?
    @AppStorage("haptiek") private var haptiek = true

    private var stemmen: [PrikStem] { alleStemmen.filter { $0.prikUID == prik.uid } }
    private var ik: UUID? { Sync.shared.gebruiker }
    private var mijnStem: PrikStem? { stemmen.first { $0.wie == ik && ik != nil } ?? stemmen.first { $0.wie == nil } }

    private func aantal(_ d: Date) -> Int { stemmen.filter { $0.ja.contains(d) }.count }
    private var beste: Date? {
        let top = prik.opties.map(aantal).max() ?? 0
        return top == 0 ? nil : prik.opties.first { aantal($0) == top }
    }

    var body: some View {
        List {
            Section {
                ForEach(prik.opties, id: \.self) { d in
                    let ja = mijnStem?.ja.contains(d) ?? false
                    Button { wissel(d) } label: {
                        HStack {
                            Image(systemName: ja ? "checkmark.circle.fill" : "circle").foregroundStyle(ja ? Color.accentColor : .secondary)
                            VStack(alignment: .leading) {
                                Text(d, format: .dateTime.weekday(.wide).day().month())
                                Text(d, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: -6) {
                                ForEach(stemmen.filter { $0.ja.contains(d) }.prefix(5)) { s in ProfielBolletje(id: s.wie, maat: 22) }
                            }
                            Text("\(aantal(d))").font(.headline.monospacedDigit())
                                .foregroundStyle(d == beste ? Color.accentColor : .primary)
                            if d == beste { Image(systemName: "star.fill").foregroundStyle(Color.accentColor) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(ja ? "Jij kunt" : "Jij kunt niet")
                }
            } header: {
                Text("Tik aan wanneer jij kunt")
            } footer: {
                Text("\(stemmen.count) \(stemmen.count == 1 ? "persoon heeft" : "mensen hebben") gestemd").font(.footnote)
            }
            if let beste {
                Section {
                    Label { Text("Beste dag: \(beste.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))") } icon: { Image(systemName: "star.fill") }
                        .foregroundStyle(Color.accentColor)
                }
            }
            Section {
                if Sync.shared.gebruiker == nil {
                    Text("Log in om deze prik met vrienden te delen.").foregroundStyle(.secondary)
                } else if let deelToken {
                    ShareLink(item: Sync.uitnodiging(deelToken), message: Text("Wanneer kun jij? \(prik.titel)")) {
                        Label("Nodig vrienden uit", systemImage: "person.badge.plus")
                    }
                } else {
                    Button { Task { deelToken = await Sync.shared.deel(prik, titel: prik.titel, soort: "prik") } } label: {
                        Label("Deel met vrienden", systemImage: "person.2")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KnivAchtergrond())
        .navigationTitle(prik.titel)
        .task { if prik.groepID != nil { deelToken = await Sync.shared.deel(prik, titel: prik.titel, soort: "prik") } }
        .sensoryFeedback(.selection, trigger: mijnStem?.ja.count ?? 0) { _, _ in haptiek }
    }

    private func wissel(_ d: Date) {
        let stem = mijnStem ?? {
            let s = PrikStem()
            s.prikUID = prik.uid
            s.wie = ik
            s.naam = Sync.shared.naam.split(separator: " ").first.map(String.init) ?? String(localized: "Ik")
            s.groepID = prik.groepID
            s.deling = prik.deling
            ctx.insert(s)
            return s
        }()
        if stem.ja.contains(d) { stem.ja.removeAll { $0 == d } } else { stem.ja.append(d) }
        stem.groepID = prik.groepID
        stem.deling = prik.deling
        stem.gewijzigd = Date()
    }
}
