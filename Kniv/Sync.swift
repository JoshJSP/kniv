import Foundation
import Supabase
import SwiftData
import SwiftUI

/// De brug naar Supabase. Contract: supabase/SYNC.md. Lokaal-eerst: SwiftData is de bron, dit synchroniseert.
enum KnivCloud {
    static let publishable = "sb_publishable_5oWWatyeuq3o-w3Qw_R_jA_qo5Tjv_l"
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://ykptlgckqppgxirtndch.supabase.co")!,
        supabaseKey: publishable
    )
}

struct Rij: Codable {
    var id: UUID
    var eigenaar: UUID
    var groep: UUID?
    var soort: String
    var data: RijData
    var gewijzigd: Date
    var gewijzigdDoor: UUID?
    var verwijderd: Bool
    var ontvangen: Date?          // door de server gezet; alleen gelezen

    enum CodingKeys: String, CodingKey {
        case id, eigenaar, groep, soort, data, gewijzigd, verwijderd, ontvangen
        case gewijzigdDoor = "gewijzigd_door"
    }
}

struct RijData: Codable {
    // notitie
    var tekst: String?
    var fotoTekst: String?
    var bakje: String?
    var gemaakt: Date?
    var items: [RijItem]?
    // timer
    var naam: String?
    var isCountdown: Bool?
    var duur: Double?
    var eind: Date?
    var rest: Double?
    var doel: Date?
    var werk: Int?
    var eenheid: String?
    // pot
    var valuta: String?
    var leden: [String]?
    // uitgave
    var pot: UUID?
    var omschrijving: String?
    var bedrag: Double?
    var betaaldDoor: String?
    var voor: [String]?
    var datum: Date?
    // prik en prikstem
    var opties: [Date]?
    var prik: UUID?
    var ja: [Date]?
    var wie: UUID?
    // notitie (extra)
    var verzegeldTot: Date?
    var garantieTot: Date?
}

struct RijItem: Codable {
    var tekst: String
    var volgorde: Int
    var door: UUID?
}

struct Profiel: Codable {
    let id: UUID
    let naam: String
    let avatar: String?
}

@MainActor @Observable final class Sync {
    static let shared = Sync()

    var gebruiker: UUID?
    var naam = ""
    var gestart = false
    var fout: String?
    var nieuwVanAnderen = 0
    var profielen: [UUID: Profiel] = [:]

    private var bezig = false
    private var nogEens = false
    private var luistert = false
    private var luisterTaak: Task<Void, Never>?
    private var gepland = 0
    private var eigenOpslag = Date.distantPast
    private let opslag = UserDefaults.standard
    private var client: SupabaseClient { KnivCloud.client }

    private var laatstOpgehaald: Date {
        get { opslag.object(forKey: "sync.opgehaald") as? Date ?? .distantPast }
        set { opslag.set(newValue, forKey: "sync.opgehaald") }
    }

    /// uid → "eigenaar,groep" van notities die weg moeten in de cloud.
    private var teVerwijderen: [String: String] {
        get { opslag.dictionary(forKey: "sync.weg") as? [String: String] ?? [:] }
        set { opslag.set(newValue, forKey: "sync.weg") }
    }

    // MARK: in- en uitloggen

    /// Sessie uit de sleutelhanger, zonder netwerk: zo blijft Kniv offline gewoon werken.
    func start() async {
        guard !gestart else { return }
        if let user = client.auth.currentUser {
            gebruiker = user.id
            naam = user.userMetadata["full_name"]?.stringValue ?? user.email ?? ""
        }
        gestart = true
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            Task { @MainActor in Sync.shared.plan() }
        }
        guard gebruiker != nil else { return }
        await nu()
        luister()
    }

    func login() async {
        fout = nil
        do {
            let sessie = try await client.auth.signInWithOAuth(provider: .google, redirectTo: URL(string: "kniv://auth"))
            wisselAccount(naar: sessie.user.id)
            gebruiker = sessie.user.id
            naam = sessie.user.userMetadata["full_name"]?.stringValue ?? sessie.user.email ?? ""
            await nu()
            luister()
        } catch {
            fout = String(localized: "Inloggen lukte niet. Probeer het nog eens.")
        }
    }

    /// Met een ander Google-account dan de vorige keer? Dan worden je lokale dingen nieuwe kopieën van dit account,
    /// anders weigert de database ze (ze horen bij het oude account) en blokkeert de hele sync.
    private func wisselAccount(naar nieuw: UUID) {
        let vorige = opslag.string(forKey: "sync.laatsteAccount").flatMap(UUID.init(uuidString:))
        opslag.set(nieuw.uuidString, forKey: "sync.laatsteAccount")
        guard let vorige, vorige != nieuw else { return }
        let ctx = KnivOpslag.container.mainContext
        func kopie<T: Synchroon>(_: T.Type) {
            for x in (try? ctx.fetch(FetchDescriptor<T>())) ?? [] {
                x.syncID = UUID()
                x.groepID = nil
                x.eigenaarID = nil
                if x.deling == "gedeeld" { x.deling = "laptop" }
                x.gesynct = nil
            }
        }
        kopie(Notitie.self); kopie(KnivTimer.self); kopie(Pot.self); kopie(Uitgave.self); kopie(Prik.self); kopie(PrikStem.self)
        for u in (try? ctx.fetch(FetchDescriptor<Uitgave>())) ?? [] { u.potUID = u.pot?.uid }
        for s in (try? ctx.fetch(FetchDescriptor<PrikStem>())) ?? [] { s.wie = nil }
        teVerwijderen = [:]
        laatstOpgehaald = .distantPast
        try? ctx.save()
    }

    func uitloggen() async {
        try? await client.auth.signOut()
        gebruiker = nil
        naam = ""
        laatstOpgehaald = .distantPast
        luisterTaak?.cancel()
        luisterTaak = nil
        luistert = false
        await client.removeAllChannels()
        // Bij opnieuw inloggen (misschien met een ander account) gaat alles weer mee.
        let ctx = KnivOpslag.container.mainContext
        ((try? ctx.fetch(FetchDescriptor<Notitie>())) ?? []).filter { $0.weggegooid == nil }.forEach { $0.gesynct = nil }
        ((try? ctx.fetch(FetchDescriptor<KnivTimer>())) ?? []).forEach { $0.gesynct = nil }
        ((try? ctx.fetch(FetchDescriptor<Pot>())) ?? []).forEach { $0.gesynct = nil }
        ((try? ctx.fetch(FetchDescriptor<Uitgave>())) ?? []).forEach { $0.gesynct = nil }
        ((try? ctx.fetch(FetchDescriptor<Prik>())) ?? []).forEach { $0.gesynct = nil }
        ((try? ctx.fetch(FetchDescriptor<PrikStem>())) ?? []).forEach { $0.gesynct = nil }
        try? ctx.save()
    }

    /// Wist het account en alles in de cloud; lokale gegevens gaan ook weg.
    func verwijderAccount() async -> Bool {
        do {
            try await client.rpc("verwijder_mij").execute()
        } catch {
            fout = error.localizedDescription
            return false
        }
        await uitloggen()
        let ctx = KnivOpslag.container.mainContext
        try? ctx.delete(model: Notitie.self)
        try? ctx.delete(model: KnivTimer.self)
        try? ctx.delete(model: Pot.self)
        try? ctx.delete(model: Uitgave.self)
        try? ctx.delete(model: Prik.self)
        try? ctx.delete(model: PrikStem.self)
        try? ctx.delete(model: Plek.self)
        try? FileManager.default.removeItem(at: Fotos.map)
        try? FileManager.default.removeItem(at: Opnames.map)
        try? ctx.save()
        teVerwijderen = [:]
        return true
    }

    // MARK: synchroniseren

    /// Kort wachten zodat een reeks wijzigingen in één keer meegaat.
    func plan() {
        guard gebruiker != nil else { return }
        // Een save die de sync zelf deed, is geen reden om opnieuw te synchroniseren.
        if Date().timeIntervalSince(eigenOpslag) < 1 { return }
        if bezig { nogEens = true; return }
        gepland += 1
        let mijn = gepland
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if mijn == gepland { await nu() }
        }
    }

    func nu() async {
        guard gebruiker != nil else { return }
        if bezig { nogEens = true; return }
        bezig = true
        repeat {
            nogEens = false
            await stuur()
            await haal()
        } while nogEens
        bezig = false
    }

    /// Onthoudt dat iets in de cloud weg moet. Sleutel "soort:uid", waarde "eigenaar,groep".
    func markeerVerwijderd(_ x: some Synchroon) {
        guard x.gesynct != nil, x.deling != "prive", let ik = gebruiker else { return }
        var weg = teVerwijderen
        weg["\(type(of: x).soort):\(x.syncID.uuidString)"] = "\((x.eigenaarID ?? ik).uuidString),\(x.groepID?.uuidString ?? "")"
        teVerwijderen = weg
    }

    private func vies<T: Synchroon>(_: T.Type, _ ctx: ModelContext) -> [T] {
        ((try? ctx.fetch(FetchDescriptor<T>())) ?? []).filter(\.isVies)
    }

    private func rij(_ x: some Synchroon, ik: UUID) -> Rij {
        Rij(id: x.syncID, eigenaar: x.eigenaarID ?? ik, groep: x.groepID, soort: type(of: x).soort, data: x.rijData(),
            gewijzigd: x.gewijzigd, gewijzigdDoor: ik, verwijderd: false)
    }

    private func stuur() async {
        guard let ik = gebruiker else { return }
        let ctx = KnivOpslag.container.mainContext
        let notities = vies(Notitie.self, ctx), timers = vies(KnivTimer.self, ctx)
        let potten = vies(Pot.self, ctx), uitgaven = vies(Uitgave.self, ctx)
        let prikken = vies(Prik.self, ctx), prikstemmen = vies(PrikStem.self, ctx)
        var rijen = notities.map { rij($0, ik: ik) } + timers.map { rij($0, ik: ik) }
        rijen += potten.map { rij($0, ik: ik) } + uitgaven.map { rij($0, ik: ik) }
        rijen += prikken.map { rij($0, ik: ik) } + prikstemmen.map { rij($0, ik: ik) }
        let weg = teVerwijderen
        for (sleutel, info) in weg {
            let delen = sleutel.split(separator: ":").map(String.init)
            let soort = delen.count == 2 ? delen[0] : "notitie"
            let uid = delen.count == 2 ? delen[1] : sleutel
            let mensen = info.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard let id = UUID(uuidString: uid), let eigenaar = UUID(uuidString: mensen.first ?? "") else { continue }
            rijen.append(Rij(id: id, eigenaar: eigenaar, groep: mensen.count > 1 ? UUID(uuidString: mensen[1]) : nil, soort: soort,
                             data: RijData(), gewijzigd: Date(), gewijzigdDoor: ik, verwijderd: true))
        }
        guard !rijen.isEmpty else { return }
        do {
            do {
                try await client.from("records").upsert(rijen).execute()
            } catch {
                // Eén rij die de database weigert, mag de rest niet tegenhouden.
                var geweigerd = 0
                for r in rijen {
                    do { try await client.from("records").upsert([r]).execute() } catch { geweigerd += 1 }
                }
                if geweigerd == rijen.count { throw error }
                fout = String(localized: "\(geweigerd) dingen konden niet synchroniseren.")
            }
            notities.forEach { $0.gesynct = $0.gewijzigd }
            timers.forEach { $0.gesynct = $0.gewijzigd }
            potten.forEach { $0.gesynct = $0.gewijzigd }
            uitgaven.forEach { $0.gesynct = $0.gewijzigd }
            prikken.forEach { $0.gesynct = $0.gewijzigd }
            prikstemmen.forEach { $0.gesynct = $0.gewijzigd }
            teVerwijderen = teVerwijderen.filter { weg[$0.key] == nil }
            eigenOpslag = Date()
            try? ctx.save()
        } catch {
            fout = error.localizedDescription
        }
    }

    private func haal() async {
        guard let ik = gebruiker else { return }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rijen: [Rij]
        do {
            rijen = try await client.from("records").select()
                // Een minuut terug: now() in de trigger is het begin van de transactie, dus een rij kan
                // met een iets oudere tijd pas na een nieuwere vastgelegd worden. Dubbel toepassen kan geen kwaad.
                .gte("ontvangen", value: iso.string(from: laatstOpgehaald.addingTimeInterval(-60)))
                .order("ontvangen").limit(1000)
                .execute().value
        } catch {
            fout = error.localizedDescription
            return
        }
        guard let laatste = rijen.last else { return }
        let ctx = KnivOpslag.container.mainContext
        // Potjes vóór uitgaven, zodat een uitgave haar potje vindt.
        pasToe(rijen, Notitie.self, ctx, ik: ik)
        pasToe(rijen, KnivTimer.self, ctx, ik: ik)
        pasToe(rijen, Pot.self, ctx, ik: ik)
        pasToe(rijen, Uitgave.self, ctx, ik: ik)
        pasToe(rijen, Prik.self, ctx, ik: ik)
        pasToe(rijen, PrikStem.self, ctx, ik: ik)
        ((try? ctx.fetch(FetchDescriptor<Uitgave>())) ?? []).forEach { $0.koppel(in: ctx) }
        let vorige = laatstOpgehaald
        laatstOpgehaald = max(laatste.ontvangen ?? laatste.gewijzigd, vorige)
        // Er is meer: meteen nog een ronde, maar alleen als de cursor voorbij de marge komt (anders dezelfde bladzijde).
        if rijen.count == 1000, laatstOpgehaald.timeIntervalSince(vorige) > 60 { nogEens = true }
        if ctx.hasChanges {
            eigenOpslag = Date()
            try? ctx.save()
        }
        var personen = Set(rijen.map(\.eigenaar))
        for r in rijen { r.data.items?.compactMap(\.door).forEach { personen.insert($0) } }
        await laadProfielen(personen)
    }

    private func pasToe<T: Synchroon>(_ rijen: [Rij], _: T.Type, _ ctx: ModelContext, ik: UUID) {
        let deze = rijen.filter { $0.soort == T.soort }
        guard !deze.isEmpty else { return }
        var lokaal: [UUID: T] = [:]
        for x in (try? ctx.fetch(FetchDescriptor<T>())) ?? [] { lokaal[x.syncID] = x }
        for r in deze {
            let bestaand = lokaal[r.id]
            if r.verwijderd {
                if let bestaand, bestaand.negeerCloudVerwijdering { continue }
                bestaand?.verwijderLokaal(in: ctx)
                lokaal[r.id] = nil
                continue
            }
            if let bestaand, bestaand.gewijzigd >= r.gewijzigd { continue }   // hier nieuwer of gelijk: laatste wint
            let x: T
            if let bestaand {
                x = bestaand
            } else {
                x = T.nieuw()
                x.syncID = r.id
                ctx.insert(x)
                lokaal[r.id] = x
            }
            x.pasToe(r.data, in: ctx)
            x.groepID = r.groep
            x.eigenaarID = r.eigenaar
            x.deling = r.groep == nil ? "laptop" : "gedeeld"
            x.gewijzigd = r.gewijzigd
            x.gesynct = r.gewijzigd
            if r.gewijzigdDoor != ik, r.groep != nil { nieuwVanAnderen += 1 }
        }
    }

    private func laadProfielen(_ ids: Set<UUID>) async {
        let onbekend = ids.filter { profielen[$0] == nil }
        guard !onbekend.isEmpty,
              let gevonden: [Profiel] = try? await client.from("profielen").select("id,naam,avatar")
                .in("id", values: onbekend.map(\.uuidString)).execute().value else { return }
        for p in gevonden { profielen[p.id] = p }
    }

    private func luister() {
        guard !luistert else { return }
        luistert = true
        luisterTaak = Task {
            let kanaal = client.channel("kniv-records")
            let stroom = kanaal.postgresChange(AnyAction.self, schema: "public", table: "records")
            await kanaal.subscribe()
            for await _ in stroom { await nu() }
        }
    }

    // MARK: delen

    private struct Groep: Codable {
        let id: UUID
        let deel_token: String
    }

    private struct NieuweGroep: Encodable {
        let eigenaar: UUID
        let soort: String
        let titel: String
    }

    /// Maakt (of vindt) de groep voor dit ding en geeft het deeltoken.
    func deel(_ x: some Synchroon, titel: String, soort: String) async -> String? {
        guard let ik = gebruiker else { return nil }
        do {
            if let g = x.groepID {
                let groep: Groep = try await client.from("groepen").select("id,deel_token").eq("id", value: g.uuidString)
                    .single().execute().value
                return groep.deel_token
            }
            let groep: Groep = try await client.from("groepen")
                .insert(NieuweGroep(eigenaar: ik, soort: soort, titel: titel), returning: .representation)
                .select("id,deel_token").single().execute().value
            x.groepID = groep.id
            x.eigenaarID = ik
            x.deling = "gedeeld"
            x.gewijzigd = Date()
            if let pot = x as? Pot {
                for u in pot.uitgaven {
                    u.groepID = groep.id
                    u.deling = "gedeeld"
                    u.gewijzigd = Date()
                }
            }
            try? KnivOpslag.container.mainContext.save()
            await nu()
            return groep.deel_token
        } catch {
            fout = error.localizedDescription
            return nil
        }
    }

    func deel(_ n: Notitie) async -> String? { await deel(n, titel: n.titel, soort: "lijst") }

    /// Uitnodigingslink geopend: lid worden en alles van die groep ophalen.
    func wordLid(_ token: String) async {
        do {
            try await client.rpc("word_lid", params: ["token": token]).execute()
            laatstOpgehaald = .distantPast
            await nu()
            AppStatus.shared.actie = "gedeeld"
        } catch {
            fout = String(localized: "Deze uitnodiging is verlopen of onbekend.")
        }
    }

    static func uitnodiging(_ token: String) -> URL { URL(string: "https://kniv.vercel.app/j/\(token)")! }
    static func bekijklink(_ token: String) -> URL { URL(string: "https://kniv.vercel.app/g/\(token)")! }
}

// MARK: schermen

struct LoginView: View {
    @State private var sync = Sync.shared
    @State private var bezig = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            LemmetVorm()
                .fill(Color.accentColor.gradient)
                .frame(width: 150, height: 44)
                .rotationEffect(.degrees(-30))
                .padding(.bottom, 20)
                .accessibilityHidden(true)
            Text("Welkom bij Kniv").font(.largeTitle.bold())
            Text("Log in om je notities ook op je laptop te zien en lijstjes met vrienden te delen.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            if let fout = sync.fout { Text(fout).font(.footnote).foregroundStyle(Color.accentColor) }
            Button {
                bezig = true
                Task {
                    await sync.login()
                    bezig = false
                }
            } label: {
                HStack {
                    if bezig { ProgressView().tint(.white) } else { Image(systemName: "person.crop.circle.fill") }
                    Text("Inloggen met Google")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(bezig)
        }
        .padding(28)
        .background(KnivAchtergrond())
    }
}

/// Klein rondje met de Google-foto of initiaal van wie iets toevoegde.
struct ProfielBolletje: View {
    let id: UUID?
    var maat: CGFloat = 20

    var body: some View {
        if let id, let p = Sync.shared.profielen[id] {
            AsyncImage(url: p.avatar.flatMap(URL.init(string:))) { beeld in
                beeld.resizable().scaledToFill()
            } placeholder: {
                Text(String(p.naam.prefix(1))).font(.system(size: maat * 0.5, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.accentColor)
            }
            .frame(width: maat, height: maat)
            .clipShape(Circle())
            .accessibilityLabel(p.naam)
        }
    }
}
