import Foundation
import SwiftData

/// Alles wat synchroniseert: notities, timers, potjes en uitgaven. Eén record per ding (supabase/SYNC.md).
@MainActor protocol Synchroon: PersistentModel {
    static var soort: String { get }
    static func nieuw() -> Self
    var syncID: UUID { get set }
    var gewijzigd: Date { get set }
    var gesynct: Date? { get set }
    var deling: String { get set }
    var groepID: UUID? { get set }
    var eigenaarID: UUID? { get set }
    func rijData() -> RijData
    func pasToe(_ d: RijData, in ctx: ModelContext)
    func verwijderLokaal(in ctx: ModelContext)
}

extension Synchroon {
    func verwijderLokaal(in ctx: ModelContext) { ctx.delete(self) }
    var isVies: Bool { deling != "prive" && (gesynct.map { gewijzigd > $0 } ?? true) }
}

extension Notitie: Synchroon {
    static var soort: String { "notitie" }
    static func nieuw() -> Notitie { Notitie(tekst: "", bron: .tekst) }
    var syncID: UUID { get { uid } set { uid = newValue } }

    func rijData() -> RijData {
        RijData(tekst: tekst, fotoTekst: fotoTekst, bakje: bakjeNaam, gemaakt: gemaakt,
                items: gesorteerdeItems.map { RijItem(tekst: $0.tekst, volgorde: $0.volgorde, door: $0.door) })
    }

    func pasToe(_ d: RijData, in ctx: ModelContext) {
        tekst = d.tekst ?? ""
        fotoTekst = d.fotoTekst ?? ""
        bakjeNaam = d.bakje
        if let gemaakt = d.gemaakt { self.gemaakt = gemaakt }
        let bakjes = ((try? ctx.fetch(FetchDescriptor<Bakje>())) ?? []).map(\.naam)
        twijfelOpties = bakjeNaam == nil ? Sorteerder.opTrefwoorden(zoekTekst, namen: bakjes) : []
        if let b = bakjeNaam, !bakjes.contains(b) { ctx.insert(Bakje(naam: b, symbool: "tray", volgorde: 100 + bakjes.count)) }
        items.forEach(ctx.delete)
        items = (d.items ?? []).map { i in
            let item = LijstItem(tekst: i.tekst, volgorde: i.volgorde)
            item.door = i.door
            return item
        }
    }

    func verwijderLokaal(in ctx: ModelContext) { Vastlegger.verwijder(self, in: ctx, uitCloud: false) }
}

extension KnivTimer: Synchroon {
    static var soort: String { "timer" }
    static func nieuw() -> KnivTimer { KnivTimer(naam: "", duur: 0) }
    var syncID: UUID { get { id } set { id = newValue } }

    func rijData() -> RijData {
        RijData(naam: naam, isCountdown: isCountdown, duur: duur, eind: eind, rest: rest, doel: doel)
    }

    func pasToe(_ d: RijData, in ctx: ModelContext) {
        naam = d.naam ?? naam
        isCountdown = d.isCountdown ?? false
        duur = d.duur ?? 0
        rest = d.rest
        doel = d.doel
        let liep = eind != nil
        eind = d.eind
        // Loopt hij op een ander apparaat, dan ook hier een melding als hij klaar is.
        if let e = d.eind, e > Date() {
            Meldingen.plan(id.uuidString, "\(naam) is klaar", na: e.timeIntervalSinceNow)
        } else if liep {
            Meldingen.annuleer(id.uuidString)
        }
    }

    func verwijderLokaal(in ctx: ModelContext) {
        Meldingen.annuleer(id.uuidString)
        ctx.delete(self)
    }
}

extension Pot: Synchroon {
    static var soort: String { "pot" }
    static func nieuw() -> Pot { Pot(naam: "", valuta: "EUR", leden: []) }
    var syncID: UUID { get { uid } set { uid = newValue } }

    func rijData() -> RijData { RijData(gemaakt: gemaakt, naam: naam, valuta: valuta, leden: leden) }

    func pasToe(_ d: RijData, in ctx: ModelContext) {
        naam = d.naam ?? naam
        valuta = d.valuta ?? "EUR"
        leden = d.leden ?? leden
        if let g = d.gemaakt { gemaakt = g }
    }
}

extension Uitgave: Synchroon {
    static var soort: String { "uitgave" }
    static func nieuw() -> Uitgave { Uitgave(omschrijving: "", bedrag: 0, betaaldDoor: "", voor: []) }
    var syncID: UUID { get { uid } set { uid = newValue } }

    func rijData() -> RijData {
        RijData(pot: pot?.uid ?? potUID, omschrijving: omschrijving, bedrag: bedrag, betaaldDoor: betaaldDoor, voor: voor, datum: datum)
    }

    func pasToe(_ d: RijData, in ctx: ModelContext) {
        omschrijving = d.omschrijving ?? ""
        bedrag = d.bedrag ?? 0
        betaaldDoor = d.betaaldDoor ?? ""
        voor = d.voor ?? []
        if let datum = d.datum { self.datum = datum }
        potUID = d.pot
        koppel(in: ctx)
    }

    /// Hangt de uitgave aan zijn potje, ook als het potje pas later binnenkwam.
    func koppel(in ctx: ModelContext) {
        guard pot == nil, let doel = potUID else { return }
        pot = ((try? ctx.fetch(FetchDescriptor<Pot>())) ?? []).first { $0.uid == doel }
    }
}
