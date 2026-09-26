import Foundation
import Supabase
import SwiftData
import SwiftUI

/// De brug naar Supabase. Contract: supabase/SYNC.md. Lokaal-eerst: SwiftData is de bron, dit synchroniseert.
enum KnivCloud {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://ykptlgckqppgxirtndch.supabase.co")!,
        supabaseKey: "sb_publishable_5oWWatyeuq3o-w3Qw_R_jA_qo5Tjv_l"
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

    enum CodingKeys: String, CodingKey {
        case id, eigenaar, groep, soort, data, gewijzigd, verwijderd
        case gewijzigdDoor = "gewijzigd_door"
    }
}

struct RijData: Codable {
    var tekst: String?
    var fotoTekst: String?
    var bakje: String?
    var gemaakt: Date?
    var items: [RijItem]?
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
    private var gepland = 0
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
            gebruiker = sessie.user.id
            naam = sessie.user.userMetadata["full_name"]?.stringValue ?? sessie.user.email ?? ""
            await nu()
            luister()
        } catch {
            fout = String(localized: "Inloggen lukte niet. Probeer het nog eens.")
        }
    }

    func uitloggen() async {
        try? await client.auth.signOut()
        gebruiker = nil
        naam = ""
        laatstOpgehaald = .distantPast
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
        try? ctx.save()
        teVerwijderen = [:]
        return true
    }

    // MARK: synchroniseren

    /// Kort wachten zodat een reeks wijzigingen in één keer meegaat.
    func plan() {
        guard gebruiker != nil, !bezig else { return }
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

    func markeerVerwijderd(_ n: Notitie) {
        guard n.gesynct != nil, let ik = gebruiker else { return }
        var weg = teVerwijderen
        weg[n.uid.uuidString] = "\((n.eigenaarID ?? ik).uuidString),\(n.groepID?.uuidString ?? "")"
        teVerwijderen = weg
    }

    private func stuur() async {
        guard let ik = gebruiker else { return }
        let ctx = KnivOpslag.container.mainContext
        let vies = ((try? ctx.fetch(FetchDescriptor<Notitie>())) ?? [])
            .filter { $0.deling != "prive" && ($0.gesynct.map { g in $0.gewijzigd > g } ?? true) }
        var rijen = vies.map { n in
            Rij(id: n.uid, eigenaar: n.eigenaarID ?? ik, groep: n.groepID, soort: "notitie",
                data: RijData(tekst: n.tekst, fotoTekst: n.fotoTekst, bakje: n.bakjeNaam, gemaakt: n.gemaakt,
                              items: n.gesorteerdeItems.map { RijItem(tekst: $0.tekst, volgorde: $0.volgorde, door: $0.door) }),
                gewijzigd: n.gewijzigd, gewijzigdDoor: ik, verwijderd: false)
        }
        let weg = teVerwijderen
        rijen += weg.compactMap { uid, info in
            let delen = info.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard let id = UUID(uuidString: uid), let eigenaar = UUID(uuidString: delen.first ?? "") else { return nil }
            return Rij(id: id, eigenaar: eigenaar, groep: delen.count > 1 ? UUID(uuidString: delen[1]) : nil, soort: "notitie",
                       data: RijData(), gewijzigd: Date(), gewijzigdDoor: ik, verwijderd: true)
        }
        guard !rijen.isEmpty else { return }
        do {
            try await client.from("records").upsert(rijen).execute()
            vies.forEach { $0.gesynct = $0.gewijzigd }
            teVerwijderen = teVerwijderen.filter { weg[$0.key] == nil }
            try? ctx.save()
            fout = nil
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
                .gte("gewijzigd", value: iso.string(from: laatstOpgehaald))
                .order("gewijzigd").limit(1000)
                .execute().value
        } catch {
            fout = error.localizedDescription
            return
        }
        guard let laatste = rijen.last else { return }

        let ctx = KnivOpslag.container.mainContext
        var lokaal: [UUID: Notitie] = [:]
        for n in (try? ctx.fetch(FetchDescriptor<Notitie>())) ?? [] { lokaal[n.uid] = n }
        let bakjes = Set(((try? ctx.fetch(FetchDescriptor<Bakje>())) ?? []).map(\.naam))
        var nieuweBakjes: Set<String> = []
        var personen: Set<UUID> = []

        for r in rijen where r.soort == "notitie" {
            let bestaand = lokaal[r.id]
            if r.verwijderd {
                if let bestaand { Vastlegger.verwijder(bestaand, in: ctx, uitCloud: false) }
                continue
            }
            if let bestaand, bestaand.gewijzigd >= r.gewijzigd { continue }   // hier nieuwer of gelijk: laatste wint
            let n = bestaand ?? {
                let nieuw = Notitie(tekst: "", bron: .tekst)
                nieuw.uid = r.id
                ctx.insert(nieuw)
                return nieuw
            }()
            n.tekst = r.data.tekst ?? ""
            n.fotoTekst = r.data.fotoTekst ?? ""
            n.bakjeNaam = r.data.bakje
            n.twijfelOpties = n.bakjeNaam == nil ? Sorteerder.opTrefwoorden(n.zoekTekst, namen: Array(bakjes)) : []
            if let gemaakt = r.data.gemaakt { n.gemaakt = gemaakt }
            n.items.forEach(ctx.delete)
            n.items = (r.data.items ?? []).map { i in
                let item = LijstItem(tekst: i.tekst, volgorde: i.volgorde)
                item.door = i.door
                if let d = i.door { personen.insert(d) }
                return item
            }
            n.groepID = r.groep
            n.eigenaarID = r.eigenaar
            n.deling = r.groep == nil ? "laptop" : "gedeeld"
            n.gewijzigd = r.gewijzigd
            n.gesynct = r.gewijzigd
            if let b = r.data.bakje, !bakjes.contains(b) { nieuweBakjes.insert(b) }
            if r.gewijzigdDoor != ik, r.groep != nil { nieuwVanAnderen += 1 }
            personen.insert(r.eigenaar)
        }
        for (i, naam) in nieuweBakjes.enumerated() {
            ctx.insert(Bakje(naam: naam, symbool: "tray", volgorde: 100 + i))
        }
        laatstOpgehaald = laatste.gewijzigd
        try? ctx.save()
        await laadProfielen(personen)
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
        Task {
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

    /// Maakt (of vindt) de groep voor deze notitie en geeft het deeltoken.
    func deel(_ n: Notitie) async -> String? {
        guard let ik = gebruiker else { return nil }
        do {
            if let g = n.groepID {
                let groep: Groep = try await client.from("groepen").select("id,deel_token").eq("id", value: g.uuidString)
                    .single().execute().value
                return groep.deel_token
            }
            let groep: Groep = try await client.from("groepen")
                .insert(NieuweGroep(eigenaar: ik, soort: "lijst", titel: n.titel), returning: .representation)
                .select("id,deel_token").single().execute().value
            n.groepID = groep.id
            n.eigenaarID = ik
            n.deling = "gedeeld"
            n.gewijzigd = Date()
            try? KnivOpslag.container.mainContext.save()
            await nu()
            return groep.deel_token
        } catch {
            fout = error.localizedDescription
            return nil
        }
    }

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
