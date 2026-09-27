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
check(Fooi.procent(eten: 5, drinken: nil, service: 1)! < Fooi.procent(eten: 1, drinken: nil, service: 5)!, "service weegt zwaarder")
let advies = Fooi.advies(prijs: 45, procent: 8)
check(advies.totaal == 49 && abs(advies.fooi - 4) < 0.001, "afronden: \(advies)")
check(Fooi.advies(prijs: 45, procent: 0).fooi == 0, "geen fooi")

check(Rad.vak(hoek: 0, aantal: 4) == 0 && Rad.vak(hoek: 1, aantal: 4) == 3, "rad: kleine draai toont vorig vak")
check(Rad.vak(hoek: 90, aantal: 4) == 3 && Rad.vak(hoek: 270, aantal: 4) == 1 && Rad.vak(hoek: 720 + 180, aantal: 4) == 2, "rad: hele rondes")
check(Rad.vak(hoek: -90, aantal: 4) == 1, "rad: tegen de klok in")
check(Rad.hoek(start: 0, snelheid: 400, remming: 200, na: 5) == 400, "rad: stopt na remtijd")
var rng = SystemRandomNumberGenerator()
let teams = Teams.verdeel(["a", "b", "c", "d", "e"], in: 2, rng: &rng)
check(teams.map(\.count).sorted() == [2, 3] && Set(teams.flatMap { $0 }).count == 5, "teams eerlijk verdeeld")
check(Stemming.winnaars(["An": ["Pizza", "Sushi"], "Bo": ["Sushi"]], opties: ["Pizza", "Sushi", "Thai"]) == ["Sushi"], "stemming")
check(Stemming.winnaars(["An": []], opties: ["Pizza"]).isEmpty, "niemand ja")

check(Gangpad.van("Melk") == .zuivel && Gangpad.van("2 appels") == .groente && Gangpad.van("wc-papier") == .huishouden, "gangpad basis")
check(Gangpad.van("pindakaas") == .kaas, "pindakaas is beleg, niet kaas-woord of zuivel")
check(Gangpad.van("volkorenbrood") == .brood, "samenstelling eindigt op brood")
check(Gangpad.van("iets raars") == .overig, "onbekend = overig")
let route = Gangpad.route(["cola", "melk", "appels", "brood"]) { $0 }
check(route.map(\.0) == [.groente, .brood, .zuivel, .drinken], "looproute-volgorde")

check(Ritme.voorkeur(uit: ["2-19": 4, "2-9": 3, "3-10": 9], weekdag: 2) == 19, "ritme: vaakste uur op maandag")
check(Ritme.voorkeur(uit: ["2-19": 2], weekdag: 2) == nil, "ritme: te weinig gegevens")
check(Ritme.voorkeur(uit: ["2-23": 9], weekdag: 2) == nil, "ritme: alleen tussen 8 en 22")
check(Ritme.voorkeur(uit: ["4-9": 5, "4-14": 5], weekdag: 4) == 9, "ritme: gelijkspel = vroegste uur")

check(Rekenmachine.uitkomst("12*3+4") == 40, "rekenen: voorrang")
check(Rekenmachine.uitkomst("(19,99 + 5) / 3").map { abs($0 - 8.33) < 0.01 } == true, "rekenen: haakjes en komma")
check(Rekenmachine.uitkomst("2^10") == 1024 && Rekenmachine.uitkomst("-3*-2") == 6, "rekenen: macht en min")
check(Rekenmachine.uitkomst("1/0") == nil && Rekenmachine.uitkomst("melk") == nil && Rekenmachine.uitkomst("06-12345678") == nil && Rekenmachine.uitkomst("10 - 3") == 7, "rekenen: grensgevallen")
check(Rekenmachine.uitkomst("42") == nil && Rekenmachine.uitkomst("3 x 4") == 12, "rekenen: los getal is geen som, x = keer")

let bonDatum = Garantie.aankoopdatum(in: "MEDIAMARKT\nDatum 14-03-2026 15:22\nTotaal 199,00", nu: zaterdag)
check(bonDatum.map { kal.component(.month, from: $0) == 3 && kal.component(.year, from: $0) == 2026 } == true, "bon: aankoopdatum")
check(Garantie.aankoopdatum(in: "datum 01/01/30", nu: zaterdag) == nil, "bon: datum in de toekomst telt niet")
check(kal.component(.year, from: Garantie.tot(bonDatum!)) == 2028, "garantie: twee jaar")
check(QRInhoud.wifi(netwerk: "Thuis;5G", wachtwoord: "a:b\\c") == "WIFI:T:WPA;S:Thuis\\;5G;P:a\\:b\\\\c;;", "wifi-QR escapen")
check(QRInhoud.wifi(netwerk: "Gast", wachtwoord: "") == "WIFI:T:nopass;S:Gast;P:;;", "wifi-QR zonder wachtwoord")
check(abs(Kompas.peiling(van: (51.58, 4.77), naar: (52.37, 4.90)) - 6) < 3, "kompas: Breda → Amsterdam is ongeveer noord")
check(abs(Kompas.peiling(van: (0, 0), naar: (0, 1)) - 90) < 0.01, "kompas: oost is 90°")

print("Alle Kniv-checks geslaagd")
