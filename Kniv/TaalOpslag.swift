import Foundation
import SwiftData

/// Een taal die je leert, met je niveau (stap in Taalniveau.codes). De eerste is je hoofdtaal.
@Model final class GekozenTaal {
    var code = ""
    var stap = 0
    var volgorde = 0
    var toegevoegd = Date()

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

    init(taal: String, woord: String, betekenis: String, zin: String) {
        self.taal = taal
        self.woord = woord
        self.betekenis = betekenis
        self.zin = zin
    }
}
