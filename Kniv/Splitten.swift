import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftData
import SwiftUI

// MARK: opslag

@Model final class Pot {
    var naam: String
    var valuta: String = "EUR"
    var leden: [String] = []
    var gemaakt: Date = Date()
    var uid: UUID = UUID()
    var gewijzigd: Date = Date()
    var gesynct: Date?
    var deling: String = "laptop"
    var groepID: UUID?
    var eigenaarID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \Uitgave.pot) var uitgaven: [Uitgave] = []

    init(naam: String, valuta: String, leden: [String]) {
        self.naam = naam
        self.valuta = valuta
        self.leden = leden
    }

    /// Wie jij bent in dit potje. Bij je eigen potje "Ik"; in een gedeeld potje van een ander kies je dat één keer.
    @MainActor var mijnNaam: String? {
        get {
            if let n = UserDefaults.standard.string(forKey: "pot.ik.\(uid)"), leden.contains(n) { return n }
            let vanMij = eigenaarID == nil || eigenaarID == Sync.shared.gebruiker
            return vanMij && leden.contains("Ik") ? "Ik" : nil
        }
        set { UserDefaults.standard.set(newValue, forKey: "pot.ik.\(uid)") }
    }

    var saldi: [String: Double] { Afrekenen.saldi(uitgaven.map { (betaaldDoor: $0.betaaldDoor, bedrag: $0.bedrag, voor: $0.voor) }) }
    var totaal: Double { uitgaven.reduce(0) { $0 + $1.bedrag } }
}

@Model final class Uitgave {
    var omschrijving: String
    var bedrag: Double
    var betaaldDoor: String
    var voor: [String]
    var datum: Date = Date()
    var pot: Pot?
    var potUID: UUID?
    var uid: UUID = UUID()
    var gewijzigd: Date = Date()
    var gesynct: Date?
    var deling: String = "laptop"
    var groepID: UUID?
    var eigenaarID: UUID?

    init(omschrijving: String, bedrag: Double, betaaldDoor: String, voor: [String]) {
        self.omschrijving = omschrijving
        self.bedrag = bedrag
        self.betaaldDoor = betaaldDoor
        self.voor = voor
    }
}

enum Koersen {
    struct Antwoord: Decodable { let rates: [String: Double] }

    /// 1 euro = zoveel vreemde valuta. Van de ECB via frankfurter.app, 12 uur bewaard, anders de laatst bekende.
    static func huidig() async -> [String: Double] {
        let d = UserDefaults.standard
        let oud = d.dictionary(forKey: "koersen") as? [String: Double] ?? [:]
        if let t = d.object(forKey: "koersenDatum") as? Date, Date().timeIntervalSince(t) < 12 * 3600, !oud.isEmpty { return oud }
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=EUR"),
              let resultaat = try? await URLSession.shared.data(from: url),
              let antwoord = try? JSONDecoder().decode(Antwoord.self, from: resultaat.0) else { return oud }
        d.set(antwoord.rates, forKey: "koersen")
        d.set(Date(), forKey: "koersenDatum")
        return antwoord.rates
    }

    static let gangbaar = ["EUR", "USD", "GBP", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "TRY", "JPY", "AUD", "CAD"]
}

func bedrag(_ tekst: String) -> Double { Double(tekst.replacingOccurrences(of: ",", with: ".")) ?? 0 }

// MARK: scherm

struct SplittenView: View {
    enum Tab: String, CaseIterable { case delen = "Delen", fooi = "Fooi", pot = "Potjes", rondjes = "Beurten", streep = "Strepen", bon = "Bon", omzetten = "Omzetten" }
    @State private var tab: Tab = .delen

    var body: some View {
        VStack(spacing: 0) {
            TabBalk(tabs: Tab.allCases, keuze: $tab) { $0.rawValue }
                .padding(.vertical, 8)
            switch tab {
            case .delen: DelenView()
            case .fooi: FooiView()
            case .pot: PottenView()
            case .rondjes: BeurtenView()
            case .streep: StreeplijstView()
            case .bon: BonView()
            case .omzetten: OmzettenView()
            }
        }
        .background(KnivAchtergrond())
        .navigationTitle("Splitten")
        .onAppear { if AppStatus.shared.bonTekst != nil { tab = .bon } }
    }
}

struct DelenView: View {
    @State private var bedragTekst = ""
    @State private var personen = 2
    @State private var fooi = 0

    private var perPersoon: Double { bedrag(bedragTekst) * (1 + Double(fooi) / 100) / Double(personen) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    TextField("0,00", text: $bedragTekst)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 52, weight: .thin, design: .rounded))
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Totaalbedrag")
                    Stepper("\(personen) personen", value: $personen, in: 1...40)
                    Picker("Fooi", selection: $fooi) {
                        ForEach([0, 5, 10, 15], id: \.self) { Text($0 == 0 ? "Geen fooi" : "\($0)%") }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(20)
                .glas(24)

                VStack(spacing: 4) {
                    Text("Per persoon").foregroundStyle(.secondary)
                    Text(perPersoon, format: .currency(code: "EUR"))
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: perPersoon)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .glas(24)

                if perPersoon > 0 { BetaalverzoekKaart(bedrag: perPersoon, waarvoor: "") }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Tekst om in WhatsApp te plakken, plus een QR-code die elke Nederlandse bankapp kan scannen (EPC/SEPA).
struct BetaalverzoekKaart: View {
    let bedrag: Double
    let waarvoor: String
    @AppStorage("iban") private var iban = ""
    @AppStorage("ibanNaam") private var naam = ""
    @State private var toonQR = false
    @State private var bewerk = false

    private var ibanKlaar: Bool { iban.count >= 15 && !naam.isEmpty }
    private var schoonIBAN: String { iban.replacingOccurrences(of: " ", with: "").uppercased() }

    private var tekst: String {
        let voor = waarvoor.isEmpty ? "" : " voor \(waarvoor)"
        return "Hoi! Je krijgt van mij nog een verzoekje: \(Omzetter.euro(bedrag))\(voor). Overmaken mag naar \(schoonIBAN) t.n.v. \(naam). Dankje! 🙏"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Betaalverzoek").font(.headline)
            if !ibanKlaar || bewerk {
                TextField("Jouw IBAN", text: $iban).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Op naam van", text: $naam)
                if ibanKlaar { Button("Klaar") { bewerk = false } }
            } else {
                HStack {
                    ShareLink(item: tekst) { Label("Stuur verzoek", systemImage: "paperplane") }
                        .buttonStyle(.borderedProminent)
                    Button { toonQR = true } label: { Label("QR", systemImage: "qrcode") }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button { bewerk = true } label: { Image(systemName: "pencil") }.accessibilityLabel("IBAN wijzigen")
                }
            }
        }
        .padding(18)
        .glas(22)
        .sheet(isPresented: $toonQR) {
            VStack(spacing: 16) {
                Text(Omzetter.euro(bedrag)).font(.largeTitle.bold())
                if let qr = QR.maak(epc) {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 280)
                        .accessibilityLabel("QR-code voor de bankapp")
                }
                Text("Scan met je bankapp").foregroundStyle(.secondary)
            }
            .padding(30)
            .presentationDetents([.medium])
        }
    }

    private var epc: String {
        ["BCD", "002", "1", "SCT", "", String(naam.prefix(70)), schoonIBAN, String(format: "EUR%.2f", bedrag), "", "",
         String((waarvoor.isEmpty ? "Kniv" : waarvoor).prefix(140))].joined(separator: "\n")
    }
}

enum QR {
    static func maak(_ tekst: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(tekst.utf8)
        filter.correctionLevel = "M"
        guard let beeld = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(beeld, from: beeld.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: fooi

struct FooiView: View {
    @State private var prijsTekst = ""
    @State private var eten: Int? = 4
    @State private var drinken: Int? = 4
    @State private var service: Int? = 4

    private var procent: Double? { Fooi.procent(eten: eten, drinken: drinken, service: service) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                TextField("Prijs zonder fooi", text: $prijsTekst)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .thin, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .glas(24)

                VStack(spacing: 16) {
                    SterrenRij(titel: "Eten", sterren: $eten)
                    Divider()
                    SterrenRij(titel: "Drinken", sterren: $drinken)
                    Divider()
                    SterrenRij(titel: "Service", sterren: $service)
                }
                .padding(20)
                .glas(24)

                uitkomst
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var uitkomst: some View {
        VStack(spacing: 6) {
            if let procent {
                let advies = Fooi.advies(prijs: bedrag(prijsTekst), procent: procent)
                Text("Normale fooi: \(Omzetter.mooi(procent))%").foregroundStyle(.secondary)
                if bedrag(prijsTekst) > 0 {
                    Text(advies.fooi, format: .currency(code: "EUR"))
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                    Text("Totaal \(Omzetter.euro(advies.totaal)), mooi afgerond").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Text("Alles staat op n.v.t., dus er valt niks te berekenen.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glas(24)
        .animation(.snappy, value: procent)
    }
}

/// Nul tot vijf sterren, of "n.v.t." zodat dit deel niet meetelt.
struct SterrenRij: View {
    let titel: LocalizedStringKey
    @Binding var sterren: Int?
    @AppStorage("haptiek") private var haptiek = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(titel).font(.headline)
                Spacer()
                Button(sterren == nil ? "Toch meetellen" : "N.v.t.") { sterren = sterren == nil ? 3 : nil }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(sterren == nil ? Color.accentColor : .secondary)
            }
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        // Nog een tik op de enige ster zet hem op nul.
                        sterren = (sterren == i && i == 1) ? 0 : i
                    } label: {
                        Image(systemName: (sterren ?? 0) >= i ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(sterren == nil ? Color.secondary.opacity(0.35) : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(sterren == nil)
                }
                Spacer()
                Text(sterren.map { "\($0)/5" } ?? "n.v.t.").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityElement()
            .accessibilityLabel(titel)
            .accessibilityValue(sterren.map { "\($0) van 5 sterren" } ?? "niet van toepassing")
            .accessibilityAdjustableAction { richting in
                guard let s = sterren else { return }
                sterren = richting == .increment ? min(s + 1, 5) : max(s - 1, 0)
            }
        }
        .sensoryFeedback(.selection, trigger: sterren) { _, _ in haptiek }
    }
}

// MARK: potjes

struct PottenView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Pot.gemaakt, order: .reverse) private var potten: [Pot]
    @State private var nieuw = false

    var body: some View {
        List {
            if potten.isEmpty {
                ContentUnavailableView("Nog geen potjes", systemImage: "person.3",
                                       description: Text("Een potje houdt bij wie wat voorschoot, bijvoorbeeld op vakantie."))
                    .listRowBackground(Color.clear)
            }
            ForEach(potten) { pot in
                NavigationLink { PotView(pot: pot) } label: {
                    VStack(alignment: .leading) {
                        Text(pot.naam).font(.headline)
                        Text("\(pot.leden.count) personen · \(Omzetter.euro(pot.totaal, pot.valuta))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { for i in $0 { potten[i].uitgaven.forEach { Sync.shared.markeerVerwijderd($0) }; Sync.shared.markeerVerwijderd(potten[i]); ctx.delete(potten[i]) } }
        }
        .scrollContentBackground(.hidden)
        .toolbar { Button { nieuw = true } label: { Image(systemName: "plus").accessibilityLabel("Nieuw potje") } }
        .sheet(isPresented: $nieuw) { NieuwePotView() }
    }
}

struct NieuwePotView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var naam = ""
    @State private var leden = "Ik, "
    @State private var valuta = "EUR"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Naam, bijv. Barcelona", text: $naam)
                TextField("Wie doen er mee? (komma's)", text: $leden)
                Picker("Valuta", selection: $valuta) { ForEach(Koersen.gangbaar, id: \.self) { Text($0) } }
            }
            .navigationTitle("Nieuw potje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Maak") {
                        let namen = leden.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        ctx.insert(Pot(naam: naam.isEmpty ? "Potje" : naam, valuta: valuta, leden: Array(NSOrderedSet(array: namen)) as? [String] ?? namen))
                        dismiss()
                    }
                    .disabled(leden.split(separator: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count < 2)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct PotView: View {
    @Bindable var pot: Pot
    @Environment(\.modelContext) private var ctx
    @State private var nieuw = false
    @State private var koersen: [String: Double] = [:]
    @State private var deelToken: String?

    var body: some View {
        List {
            if pot.mijnNaam == nil {
                Section {
                    Picker("Wie ben jij in dit potje?", selection: Binding(get: { pot.mijnNaam ?? "" }, set: { pot.mijnNaam = $0 })) {
                        Text("Kies…").tag("")
                        ForEach(pot.leden, id: \.self) { Text($0).tag($0) }
                    }
                } footer: {
                    Text("Dan weet Kniv wat jij nog krijgt of moet betalen.")
                }
            }
            Section("Afrekenen") {
                let betalingen = Afrekenen.minsteBetalingen(pot.saldi)
                if betalingen.isEmpty { Text("Iedereen staat quitte.").foregroundStyle(.secondary) }
                ForEach(Array(betalingen.enumerated()), id: \.offset) { _, b in
                    HStack {
                        Text("\(b.van) → \(b.naar)")
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(Omzetter.euro(b.bedrag, pot.valuta)).bold()
                            if pot.valuta != "EUR", let r = koersen[pot.valuta] {
                                Text("≈ \(Omzetter.euro(b.bedrag / r))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section("Uitgaven") {
                ForEach(pot.uitgaven.sorted { $0.datum > $1.datum }) { u in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(u.omschrijving.isEmpty ? "Uitgave" : u.omschrijving)
                            Text("\(u.betaaldDoor) betaalde · voor \(u.voor.count == pot.leden.count ? "iedereen" : u.voor.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Omzetter.euro(u.bedrag, pot.valuta))
                    }
                    .swipeActions { Button("Verwijder", role: .destructive) { Sync.shared.markeerVerwijderd(u); ctx.delete(u) } }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KnivAchtergrond())
        .navigationTitle(pot.naam)
        .toolbar {
            Button {
                Task { deelToken = await Sync.shared.deel(pot, titel: pot.naam, soort: "pot") }
            } label: { Image(systemName: pot.groepID == nil ? "person.badge.plus" : "person.2.fill").accessibilityLabel("Deel potje") }
            .disabled(Sync.shared.gebruiker == nil)
            Button { nieuw = true } label: { Image(systemName: "plus").accessibilityLabel("Uitgave") }
        }
        .sheet(isPresented: $nieuw) { NieuweUitgaveView(pot: pot) }
        .sheet(item: Binding(get: { deelToken.map(DeelToken.init) }, set: { deelToken = $0?.token })) { t in
            VStack(spacing: 18) {
                Image(systemName: "person.2.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                Text("Deel \(pot.naam)").font(.title2.bold())
                Text("Wie meedoet logt in met Google en kan zelf uitgaven toevoegen. De link verloopt na 30 dagen.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                ShareLink(item: Sync.uitnodiging(t.token), message: Text("Doe mee met ons potje in Kniv")) {
                    Label("Nodig iemand uit", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(28)
            .presentationDetents([.medium])
        }
        .task { koersen = await Koersen.huidig() }
    }
}

struct NieuweUitgaveView: View {
    let pot: Pot
    @Environment(\.dismiss) private var dismiss
    @State private var omschrijving = ""
    @State private var bedragTekst = ""
    @State private var betaaldDoor = ""
    @State private var voor: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("Waarvoor?", text: $omschrijving)
                TextField("Bedrag in \(pot.valuta)", text: $bedragTekst).keyboardType(.decimalPad)
                Picker("Betaald door", selection: $betaaldDoor) { ForEach(pot.leden, id: \.self) { Text($0) } }
                Section("Voor wie") {
                    ForEach(pot.leden, id: \.self) { lid in
                        Toggle(lid, isOn: Binding(get: { voor.contains(lid) }, set: { if $0 { voor.insert(lid) } else { voor.remove(lid) } }))
                    }
                }
            }
            .navigationTitle("Uitgave")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                betaaldDoor = pot.mijnNaam ?? pot.leden.first ?? ""
                voor = Set(pot.leden)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") {
                        let u = Uitgave(omschrijving: omschrijving, bedrag: bedrag(bedragTekst), betaaldDoor: betaaldDoor,
                                        voor: pot.leden.filter(voor.contains))
                        u.groepID = pot.groepID
                        u.deling = pot.deling
                        pot.uitgaven.append(u)
                        dismiss()
                    }
                    .disabled(bedrag(bedragTekst) <= 0 || voor.isEmpty)
                }
            }
        }
    }
}

// MARK: bon

struct BonView: View {
    @State private var regels: [BonParser.Regel] = []
    @State private var wie: [Int: Set<String>] = [:]
    @State private var mensen = "Ik, "
    @State private var toonCamera = false
    @State private var bezig = false

    private var namen: [String] {
        mensen.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var perPersoon: [(String, Double)] {
        namen.map { naam in
            (naam, regels.indices.reduce(0) { som, i in
                let delers = wie[i] ?? []
                return delers.contains(naam) ? som + regels[i].prijs / Double(delers.count) : som
            })
        }
    }

    var body: some View {
        List {
            UitgavenKaart()
            Section {
                Button { toonCamera = true } label: { Label(regels.isEmpty ? "Scan een bon" : "Andere bon scannen", systemImage: "doc.viewfinder") }
                TextField("Wie waren er? (komma's)", text: $mensen)
            }
            if bezig { ProgressView("Bon lezen…") }
            if !regels.isEmpty {
                Section("Tik aan wie wat had") {
                    ForEach(regels.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(regels[i].naam); Spacer(); Text(Omzetter.euro(regels[i].prijs)) }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(namen, id: \.self) { naam in
                                        let aan = wie[i, default: []].contains(naam)
                                        Button(naam) {
                                            if aan { wie[i, default: []].remove(naam) } else { wie[i, default: []].insert(naam) }
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(aan ? Color.accentColor : .secondary)
                                        .accessibilityAddTraits(aan ? .isSelected : [])
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Per persoon") {
                    ForEach(perPersoon, id: \.0) { p in
                        HStack { Text(p.0); Spacer(); Text(Omzetter.euro(p.1)).bold() }
                    }
                    ShareLink(item: perPersoon.map { "\($0.0): \(Omzetter.euro($0.1))" }.joined(separator: "\n")) {
                        Label("Deel verdeling", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .fullScreenCover(isPresented: $toonCamera) {
            DocumentCamera { beeld in
                toonCamera = false
                guard let beeld else { return }
                bezig = true
                Task {
                    lees(await TekstHerkenning.lees(beeld))
                    bezig = false
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if let t = AppStatus.shared.bonTekst {
                AppStatus.shared.bonTekst = nil
                lees(t)
            }
        }
    }

    private func lees(_ tekst: String) {
        regels = BonParser.regels(tekst)
        wie = Dictionary(uniqueKeysWithValues: regels.indices.map { ($0, Set(namen)) })
    }
}

// MARK: omzetten

struct OmzettenView: View {
    @State private var invoer = ""
    @State private var koersen: [String: Double] = [:]
    @State private var toonCamera = false
    @FocusState private var focus: Bool

    private let voorbeelden = ["3 cups bloem", "45 usd", "30% korting op 89", "10 km in mijl", "350 f", "9:15 tot 17:30", "14:35 + 2u50", "dagen tot 25 dec", "15:00 in tokyo", "2,49 voor 500g of 3,99 voor 1kg"]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    TextField("Typ iets om om te zetten", text: $invoer)
                        .font(.title3)
                        .focused($focus)
                        .submitLabel(.done)
                    Button { toonCamera = true } label: { Image(systemName: "camera") }
                        .accessibilityLabel("Prijskaartje fotograferen")
                }
                .padding(18)
                .glas(22)

                if let uitkomst = Omzetter.reken(invoer, koersen: koersen) {
                    Text(uitkomst)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(22)
                        .glas(24)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else if !invoer.isEmpty {
                    Text("Nog geen idee wat ik hiermee moet. Probeer bijvoorbeeld \"12 oz\" of \"20 gbp\".")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Probeer").font(.headline)
                    FlowRij(items: voorbeelden) { v in Button(v) { invoer = v }.buttonStyle(.bordered) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .animation(.snappy, value: invoer)
        }
        .task { koersen = await Koersen.huidig() }
        .fullScreenCover(isPresented: $toonCamera) {
            DocumentCamera { beeld in
                toonCamera = false
                guard let beeld else { return }
                Task { invoer = prijs(in: await TekstHerkenning.lees(beeld)) ?? invoer }
            }
            .ignoresSafeArea()
        }
    }

    /// Eerste bedrag met valutateken of -code op het prijskaartje.
    private func prijs(in tekst: String) -> String? {
        for regel in tekst.components(separatedBy: .newlines) {
            let klein = regel.lowercased()
            if Omzetter.valuta(klein, koersen) != nil { return klein }
        }
        return nil
    }
}

/// Knoppen die netjes doorlopen naar de volgende regel.
struct FlowRij<Item: Hashable, Inhoud: View>: View {
    let items: [Item]
    @ViewBuilder let inhoud: (Item) -> Inhoud

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { ForEach(items, id: \.self, content: inhoud) }
            VStack(alignment: .leading) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                    HStack { ForEach(items[i..<min(i + 2, items.count)], id: \.self, content: inhoud) }
                }
            }
        }
    }
}

struct DeelToken: Identifiable {
    let token: String
    var id: String { token }
}
