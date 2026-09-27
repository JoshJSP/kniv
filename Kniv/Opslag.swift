import Foundation
import SwiftData
import UIKit

@Model final class Bakje {
    var naam: String
    var symbool: String
    var volgorde: Int
    var vast: Bool
    var vergrendeld: Bool = false
    var laatstGebruikt: Date = Date.distantPast

    init(naam: String, symbool: String, volgorde: Int, vast: Bool = false) {
        self.naam = naam
        self.symbool = symbool
        self.volgorde = volgorde
        self.vast = vast
    }

    static let symbolen = ["School": "graduationcap", "Boodschappen": "cart", "Ideeën": "lightbulb",
                           "To-do": "checklist", "Persoonlijk": "person"]
}

enum Bron: String {
    case tekst, spraak, foto, siri
}

@Model final class Notitie {
    var gemaakt: Date = Date()
    var gewijzigd: Date = Date()
    var tekst: String = ""
    var fotoTekst: String = ""
    var fotoBestand: String?
    var bakjeNaam: String?
    var twijfelOpties: [String] = []
    var bronRuw: String = Bron.tekst.rawValue
    // sync (supabase/SYNC.md)
    var uid: UUID = UUID()
    var gesynct: Date?
    var deling: String = "laptop"      // prive, laptop, gedeeld
    var groepID: UUID?
    var eigenaarID: UUID?
    var garantieTot: Date?
    var verzegeldTot: Date?
    var audioBestand: String?
    @Relationship(deleteRule: .cascade, inverse: \LijstItem.notitie) var items: [LijstItem] = []

    init(tekst: String, bron: Bron, fotoBestand: String? = nil) {
        self.tekst = tekst
        self.bronRuw = bron.rawValue
        self.fotoBestand = fotoBestand
    }

    var isLijst: Bool { !items.isEmpty }
    var gesorteerdeItems: [LijstItem] { items.sorted { $0.volgorde < $1.volgorde } }
    var zoekTekst: String { ([tekst, fotoTekst] + items.map(\.tekst)).joined(separator: "\n") }
    var isVerzegeld: Bool { verzegeldTot.map { $0 > Date() } ?? false }

    var titel: String {
        let eerste = tekst.split(separator: "\n").first.map(String.init)
            ?? gesorteerdeItems.first?.tekst
            ?? fotoTekst.split(separator: "\n").first.map(String.init)
        return eerste ?? (fotoBestand == nil ? "Leeg" : "Foto")
    }
}

@Model final class LijstItem {
    var tekst: String
    var volgorde: Int
    var notitie: Notitie?
    var door: UUID?

    init(tekst: String, volgorde: Int) {
        self.tekst = tekst
        self.volgorde = volgorde
    }
}

enum KnivOpslag {
    static let container: ModelContainer = {
        do { return try ModelContainer(for: Notitie.self, LijstItem.self, Bakje.self, KnivTimer.self, Pot.self, Uitgave.self, Plek.self, Prik.self, PrikStem.self) }
        catch { fatalError("Kniv-opslag kon niet openen: \(error)") }
    }()

    /// Na de update met sync kregen bestaande notities misschien allemaal dezelfde uid; maak ze uniek.
    @MainActor static func herstelUIDs() {
        let ctx = container.mainContext
        var gezien: Set<UUID> = []
        for n in (try? ctx.fetch(FetchDescriptor<Notitie>())) ?? [] {
            if !gezien.insert(n.uid).inserted { n.uid = UUID(); n.gesynct = nil }
        }
        for p in (try? ctx.fetch(FetchDescriptor<Pot>())) ?? [] {
            if !gezien.insert(p.uid).inserted { p.uid = UUID(); p.gesynct = nil }
        }
        for u in (try? ctx.fetch(FetchDescriptor<Uitgave>())) ?? [] {
            if !gezien.insert(u.uid).inserted { u.uid = UUID(); u.gesynct = nil }
        }
        for t in (try? ctx.fetch(FetchDescriptor<KnivTimer>())) ?? [] {
            if !gezien.insert(t.id).inserted { t.id = UUID(); t.gesynct = nil }
        }
        try? ctx.save()
    }

    @MainActor static func zaaiBakjes() {
        let ctx = container.mainContext
        guard ((try? ctx.fetchCount(FetchDescriptor<Bakje>())) ?? 0) == 0 else { return }
        for (i, naam) in Sorteerder.standaardBakjes.enumerated() {
            ctx.insert(Bakje(naam: naam, symbool: Bakje.symbolen[naam] ?? "tray", volgorde: i, vast: true))
        }
        try? ctx.save()
    }
}

/// Alles wat een notitie maakt, sorteert of weggooit. Gedeeld door het scherm, Siri en de Actieknop.
@MainActor enum Vastlegger {
    @discardableResult
    static func bewaar(_ tekst: String, bron: Bron, foto: String? = nil, fotoTekst: String = "", in ctx: ModelContext) -> Notitie? {
        let schoon = tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !schoon.isEmpty || foto != nil else { return nil }
        let delen = NotitieParser.ontleed(schoon)
        let n = Notitie(tekst: delen.rest, bron: bron, fotoBestand: foto)
        n.fotoTekst = fotoTekst
        ctx.insert(n)
        for (i, tekst) in delen.items.enumerated() {
            let item = LijstItem(tekst: tekst, volgorde: i)
            item.door = Sync.shared.gebruiker
            n.items.append(item)
        }
        try? ctx.save()
        return n
    }

    static func sorteer(_ n: Notitie, in ctx: ModelContext) async {
        let bakjes = ((try? ctx.fetch(FetchDescriptor<Bakje>())) ?? []).map(\.naam)
        let opties = await Sorteerder.sorteer(n.zoekTekst, bakjes: bakjes)
        if opties.count == 1 {
            kies(opties[0], voor: n, in: ctx, leer: false)
        } else {
            n.twijfelOpties = opties
        }
        try? ctx.save()
    }

    static func kies(_ naam: String, voor n: Notitie, in ctx: ModelContext, leer: Bool) {
        n.bakjeNaam = naam
        n.twijfelOpties = []
        n.gewijzigd = Date()
        let gezocht = naam
        if let b = try? ctx.fetch(FetchDescriptor<Bakje>(predicate: #Predicate { $0.naam == gezocht })).first {
            b.laatstGebruikt = Date()
        }
        if leer { Sorteerder.leer(n.zoekTekst, bakje: naam) }
        try? ctx.save()
    }

    static func verwijder(_ n: Notitie, in ctx: ModelContext, uitCloud: Bool = true) {
        if uitCloud && n.deling != "prive" { Sync.shared.markeerVerwijderd(n) }
        if let f = n.fotoBestand { try? FileManager.default.removeItem(at: Fotos.url(f)) }
        if let a = n.audioBestand { try? FileManager.default.removeItem(at: Opnames.url(a)) }
        ctx.delete(n)
        try? ctx.save()
    }
}

enum Fotos {
    static var map: URL {
        let u = URL.documentsDirectory.appending(path: "fotos")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func url(_ naam: String) -> URL { map.appending(path: naam) }

    static func bewaar(_ beeld: UIImage) -> String? {
        let naam = UUID().uuidString + ".jpg"
        guard let data = beeld.jpegData(compressionQuality: 0.8), (try? data.write(to: url(naam))) != nil else { return nil }
        return naam
    }

    private static let cache = NSCache<NSString, UIImage>()

    static func miniatuur(_ naam: String) -> UIImage? {
        if let c = cache.object(forKey: naam as NSString) { return c }
        guard let beeld = UIImage(contentsOfFile: url(naam).path) else { return nil }
        let schaal = 400 / max(beeld.size.width, beeld.size.height, 1)
        let mini = beeld.preparingThumbnail(of: CGSize(width: beeld.size.width * schaal, height: beeld.size.height * schaal)) ?? beeld
        cache.setObject(mini, forKey: naam as NSString)
        return mini
    }
}

/// Seintje van Siri of de Actieknop naar de schermen.
@Observable final class AppStatus {
    static let shared = AppStatus()
    var startInspreken = false
    /// Snelle actie uit een widget of Control Center: "tekst", "foto" of "lijst".
    var actie: String?
    var openTimers = false
    var openSplitten = false
    var bonTekst: String?
    var openKiezen = false
    var kiesOpties: [String]?
    var kiesTab = "Rad"
    var inDobbelmesje = false
}

struct VersieInfo: Decodable {
    let versie: String
    let mesnaam: String
    let nieuw: [String]

    static let huidig: VersieInfo? = Bundle.main.url(forResource: "versie", withExtension: "json")
        .flatMap { try? JSONDecoder().decode(VersieInfo.self, from: Data(contentsOf: $0)) }
}
