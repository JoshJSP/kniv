import Foundation
import SwiftData

/// Een taal die je leert, met je niveau (stap in Taalniveau.codes). De eerste is je hoofdtaal.
@Model final class GekozenTaal {
    var code = ""
    var stap = 0
    var volgorde = 0
    var toegevoegd = Date()
    var uid: UUID = UUID()
    var gewijzigd: Date = Date()
    var gesynct: Date?
    var deling: String = "laptop"
    var groepID: UUID?
    var eigenaarID: UUID?

    init(code: String, stap: Int, volgorde: Int) {
        self.code = code
        self.stap = stap
        self.volgorde = volgorde
    }
}

/// Een gemaakt leesstukje, om terug te lezen of opnieuw te luisteren.
@Model final class Leesstuk {
    var taal = ""
    var titel = ""
    var tekst = ""
    var onderwerp = ""
    var niveau = ""
    var gemaakt = Date()
    var woorden: [String: String] = [:]   // woord in kleine letters → Nederlandse betekenis
    var vragenJSON = ""                   // begripsvragen (Oefenen.bewaar), leeg = nog niet gemaakt
    var uid: UUID = UUID()
    var gewijzigd: Date = Date()
    var gesynct: Date?
    var deling: String = "laptop"
    var groepID: UUID?
    var eigenaarID: UUID?

    init(taal: String, titel: String, tekst: String, onderwerp: String, niveau: String, woorden: [String: String]) {
        self.taal = taal
        self.titel = titel
        self.tekst = tekst
        self.onderwerp = onderwerp
        self.niveau = niveau
        self.woorden = woorden
    }
}

/// Een woord uit Mijn woorden, met de zin waarin het stond.
@Model final class BewaardWoord {
    var taal = ""
    var woord = ""
    var betekenis = ""
    var zin = ""
    var gemaakt = Date()
    var uid: UUID = UUID()
    var gewijzigd: Date = Date()
    var gesynct: Date?
    var deling: String = "laptop"
    var groepID: UUID?
    var eigenaarID: UUID?

    init(taal: String, woord: String, betekenis: String, zin: String) {
        self.taal = taal
        self.woord = woord
        self.betekenis = betekenis
        self.zin = zin
    }
}

// MARK: sync (soorten taal, leesstuk, woord; zie supabase/SYNC.md). Nooit gedeeld: groep is altijd nil.

extension GekozenTaal: Synchroon {
    static var soort: String { "taal" }
    static func nieuw() -> GekozenTaal { GekozenTaal(code: "", stap: 0, volgorde: 0) }
    var syncID: UUID { get { uid } set { uid = newValue } }
    func rijData() -> RijData { RijData(gemaakt: toegevoegd, taal: code, stap: stap, volgorde: volgorde) }
    func pasToe(_ d: RijData, in ctx: ModelContext) {
        code = d.taal ?? code
        stap = d.stap ?? stap
        volgorde = d.volgorde ?? volgorde
        if let g = d.gemaakt { toegevoegd = g }
    }
}

extension Leesstuk: Synchroon {
    static var soort: String { "leesstuk" }
    static func nieuw() -> Leesstuk { Leesstuk(taal: "", titel: "", tekst: "", onderwerp: "", niveau: "", woorden: [:]) }
    var syncID: UUID { get { uid } set { uid = newValue } }
    func rijData() -> RijData {
        RijData(tekst: tekst, gemaakt: gemaakt, taal: taal, titel: titel, onderwerp: onderwerp, niveau: niveau, woorden: woorden, vragen: vragenJSON)
    }
    func pasToe(_ d: RijData, in ctx: ModelContext) {
        taal = d.taal ?? taal
        titel = d.titel ?? titel
        tekst = d.tekst ?? tekst
        onderwerp = d.onderwerp ?? onderwerp
        niveau = d.niveau ?? niveau
        woorden = d.woorden ?? woorden
        vragenJSON = d.vragen ?? vragenJSON
        if let g = d.gemaakt { gemaakt = g }
    }
}

extension BewaardWoord: Synchroon {
    static var soort: String { "woord" }
    static func nieuw() -> BewaardWoord { BewaardWoord(taal: "", woord: "", betekenis: "", zin: "") }
    var syncID: UUID { get { uid } set { uid = newValue } }
    func rijData() -> RijData { RijData(gemaakt: gemaakt, taal: taal, woord: woord, betekenis: betekenis, zin: zin) }
    func pasToe(_ d: RijData, in ctx: ModelContext) {
        taal = d.taal ?? taal
        woord = d.woord ?? woord
        betekenis = d.betekenis ?? betekenis
        zin = d.zin ?? zin
        if let g = d.gemaakt { gemaakt = g }
    }
}
