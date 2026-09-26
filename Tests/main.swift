// Snelle check van de logica, zonder simulator: swiftc Kniv/Logica/*.swift Tests/main.swift
import Foundation

func check(_ ok: Bool, _ wat: String) {
    if !ok { print("FOUT: \(wat)"); exit(1) }
}

let lijst = NotitieParser.ontleed("Boodschappen\n- melk\n- eieren\n• kaas\n- ")
check(lijst.items == ["melk", "eieren", "kaas"], "lijstje herkennen")
check(lijst.rest == "Boodschappen", "titel boven lijstje")
check(NotitieParser.ontleed("gewoon een zin - met streepje").items.isEmpty, "geen lijstje in gewone zin")

let namen = Sorteerder.standaardBakjes
check(Sorteerder.opTrefwoorden("melk en eieren halen bij de jumbo", namen: namen) == ["Boodschappen"], "boodschappen")
check(Sorteerder.opTrefwoorden("tentamen H3 leren", namen: namen) == ["School"], "school")
check(Sorteerder.opTrefwoorden("xyz qwerty", namen: namen) == ["Ideeën", "To-do"], "twijfel bij onbekend")
check(Sorteerder.opTrefwoorden("Ahoy daar", namen: namen) != ["Boodschappen"], "'ah' alleen als los woord")

let kal = Calendar.current
let zaterdag = DateComponents(calendar: kal, year: 2026, month: 9, day: 26, hour: 10).date!
let morgen = Herinnering.vind(in: "morgen oma bellen", nu: zaterdag)
check(morgen?.heeftTijd == false && kal.component(.day, from: morgen!.dag) == 27, "morgen zonder tijd")
let maandag = Herinnering.vind(in: "maandag om 14:30 tandarts", nu: zaterdag)
check(maandag?.heeftTijd == true && kal.component(.day, from: maandag!.dag) == 28 && kal.component(.hour, from: maandag!.dag) == 14, "maandag 14:30")
check(kal.component(.month, from: Herinnering.vind(in: "deadline 9 okt", nu: zaterdag)!.dag) == 10, "9 okt")
check(kal.component(.year, from: Herinnering.vind(in: "feestje 3 mei", nu: zaterdag)!.dag) == 2027, "voorbije datum = volgend jaar")
check(kal.component(.day, from: Herinnering.vind(in: "om 9 bellen", nu: zaterdag)!.dag) == 27, "tijd al voorbij = morgen")
check(Herinnering.vind(in: "gewoon tekst zonder moment", nu: zaterdag) == nil, "geen moment")
check(Herinnering.vind(in: "morgenochtend", nu: zaterdag) == nil, "morgenochtend is (nog) geen match")

let oven = TimerParser.vind(in: "over 20 min oven uit")
check(oven?.naam == "Oven uit" && oven?.seconden == 1200, "timer uit notitie")
check(TimerParser.vind(in: "pasta 9 minuten")?.seconden == 540, "pasta 9 minuten")
check(TimerParser.vind(in: "1 uur")?.naam == "Timer", "naamloze timer")
check(TimerParser.vind(in: "tandarts om 14:30") == nil, "kloktijd is geen timer")
check(TimerParser.klok(125) == "02:05" && TimerParser.klok(3725) == "1:02:05", "klokweergave")

let saldi = Afrekenen.saldi([("A", 90, ["A", "B", "C"]), ("B", 30, ["A", "B", "C"])])
let betalingen = Afrekenen.minsteBetalingen(saldi)
check(betalingen == [.init(van: "C", naar: "A", bedrag: 40), .init(van: "B", naar: "A", bedrag: 10)], "minste betalingen: \(betalingen)")

let bon = BonParser.regels("ALBERT HEIJN\nMelk 1,29\nBrood 2,49\nTOTAAL 3,78\nPIN 3,78")
check(bon == [.init(naam: "Melk", prijs: 1.29), .init(naam: "Brood", prijs: 2.49)], "bon lezen: \(bon)")
check(BonParser.lijktBon("Melk 1,29\nBrood 2,49\nTotaal 3,78"), "bon herkennen")
check(!BonParser.lijktBon("morgen oma bellen"), "notitie is geen bon")

Omzetter.locale = Locale(identifier: "nl_NL")
let bloem = Omzetter.reken("3 cups bloem") ?? ""
check(bloem.contains("720 ml") && bloem.contains("375 g bloem"), "cups bloem: \(bloem)")
check((Omzetter.reken("10 mijl") ?? "").contains("16,1 km"), "mijl: \(Omzetter.reken("10 mijl") ?? "nil")")
check((Omzetter.reken("100 f") ?? "").contains("37,8 °C"), "fahrenheit: \(Omzetter.reken("100 f") ?? "nil")")
check((Omzetter.reken("10 km in mijl") ?? "").contains("6,21 mijl"), "km in mijl")
check((Omzetter.reken("30% korting op 89") ?? "").contains("62,30"), "korting: \(Omzetter.reken("30% korting op 89") ?? "nil")")
check((Omzetter.reken("45 usd", koersen: ["USD": 1.1]) ?? "").contains("40,91"), "valuta: \(Omzetter.reken("45 usd", koersen: ["USD": 1.1]) ?? "nil")")
check((Omzetter.reken("$12.99", koersen: ["USD": 1.1]) ?? "").contains("11,81"), "dollarteken")
check(Omzetter.reken("gewoon tekst") == nil, "geen omzetting")

check(Fooi.procent(eten: 5, drinken: 5, service: 5) == 15, "fooi 5 sterren")
check(Fooi.procent(eten: nil, drinken: nil, service: nil) == nil, "alles n.v.t.")
check(Fooi.procent(eten: 0, drinken: nil, service: 0) == 0, "0 sterren, drinken n.v.t.")
check(Fooi.procent(eten: 3, drinken: nil, service: 3) == 8, "3 sterren = 8%")
check(Fooi.procent(eten: 5, drinken: 5, service: 1)! < Fooi.procent(eten: 1, drinken: 1, service: 5)!, "service weegt zwaarder")
let advies = Fooi.advies(prijs: 45, procent: 8)
check(advies.totaal == 49 && abs(advies.fooi - 4) < 0.001, "afronden: \(advies)")
check(Fooi.advies(prijs: 45, procent: 0).fooi == 0, "geen fooi")

print("Alle Kniv-checks geslaagd")
