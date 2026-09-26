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

print("Alle Kniv-checks geslaagd")
