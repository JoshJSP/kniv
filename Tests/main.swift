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
check(advies.totaal == 49 && abs(advies.fooi - 4) < 0.001, "afronden naar boven op halve euro: \(advies)")
check(Fooi.advies(prijs: 3, procent: 8).fooi == 0.5, "kleine fooi wordt geen €0")
check(Fooi.advies(prijs: 40, procent: 8).totaal == 43.5 && Fooi.advies(prijs: 10, procent: 0).totaal == 10, "afronden: halve euro omhoog, geen fooi = prijs")
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

let droog = (10...18).map { Weer.Uur(uur: $0, kans: 5, mm: 0, temp: 15) }
check(Weer.advies(droog) == nil, "weer: droog en mild = geen advies")
var nat = droog
nat[5] = Weer.Uur(uur: 15, kans: 70, mm: 1.2, temp: 14)
check(Weer.advies(nat)?.contains("15:00") == true, "weer: regen rond 15:00")
check(Weer.advies([Weer.Uur(uur: 8, kans: 0, mm: 0, temp: 4)])?.contains("4°") == true, "weer: koud = jas")
check(Verjaardag.vind(in: "verjaardag Sam 12 mei").map { $0.dag == 12 && $0.maand == 5 } == true, "verjaardag met maandnaam")
check(Verjaardag.vind(in: "Lisa jarig 3-4").map { $0.dag == 3 && $0.maand == 4 } == true, "verjaardag met d-m")
check(Verjaardag.vind(in: "tandarts 12 mei") == nil, "geen verjaardag zonder dat woord")
check(Studieplan.werk(uit: "120 pagina's").map { $0.aantal == 120 && $0.eenheid == "pagina's" } == true, "studieplan: werk lezen")
check(Studieplan.perDag(werk: 120, dagen: 11) == 11 && Studieplan.perDag(werk: 5, dagen: 0) == 5, "studieplan: per dag afronden")

check(Uitlenen.vind(in: "Sam heeft mijn oplader").map { $0.wie == "Sam" && $0.wat == "oplader" } == true, "uitlenen: X heeft mijn Y")
check(Uitlenen.vind(in: "boek geleend aan Lisa").map { $0.wie == "Lisa" && $0.wat == "boek" } == true, "uitlenen: Y geleend aan X")
check(Uitlenen.vind(in: "mijn fiets uitgeleend aan Tom").map { $0.wie == "Tom" && $0.wat == "fiets" } == true, "uitlenen: mijn Y uitgeleend aan X")
check(Uitlenen.vind(in: "morgen oma bellen") == nil, "uitlenen: gewone notitie")

let wekker = DateComponents(calendar: kal, year: 2026, month: 9, day: 28, hour: 7, minute: 30).date!
let bed = Slaap.bedtijden(wakker: wekker)
check(kal.component(.hour, from: bed[0].tijd) == 22 && kal.component(.minute, from: bed[0].tijd) == 15 && bed[0].cycli == 6, "slaap: 6 cycli voor 7:30 = 22:15")
check(kal.component(.hour, from: bed[2].tijd) == 1 && kal.component(.minute, from: bed[2].tijd) == 15, "slaap: 4 cycli = 1:15")
check(Slaap.wektijden(vanaf: wekker)[0].tijd.timeIntervalSince(wekker) == 6.25 * 3600, "slaap: nu slapen, over 6u15 wakker")

check(Gehoor.veiligeMinuten(bij: 85) == 480 && Gehoor.veiligeMinuten(bij: 100) == 15, "gehoor: 85 dB 8 uur, 100 dB 15 min")
check(Gehoor.veiligeMinuten(bij: 60) == .infinity, "gehoor: rustig is onbeperkt")
check(abs(Gehoor.portie([(db: 100, seconden: 450)]) - 0.5) < 0.001, "gehoor: 7,5 min bij 100 dB = halve portie")

check(BonParser.totaal("Melk 1,29\nBrood 2,49\nSubtotaal 3,78\nTOTAAL 3,78\nPIN 3,78") == 3.78, "bon: totaalregel")
check(BonParser.totaal("Melk 1,29\nBrood 2,49").map { abs($0 - 3.78) < 0.001 } == true, "bon: som als er geen totaal staat")
check(BonParser.totaal("gewoon tekst") == nil, "bon: geen bedragen")

check(kal.component(.hour, from: Herinnering.vind(in: "morgen om 3 bellen", nu: zaterdag)!.dag) == 15, "om 3 = 15:00")
check(kal.component(.hour, from: Herinnering.vind(in: "morgen om 3 uur 's ochtends vroeg", nu: zaterdag)!.dag) == 3, "om 3 's ochtends vroeg = 3:00")
check(Herinnering.vind(in: "morgen melk 2.50", nu: zaterdag)?.heeftTijd == false, "prijs is geen tijd")

check(Morse.code("SOS") == "... --- ...", "morse: sos")
check(Morse.code("hé jij") == ".... . / .--- .. .---", "morse: woorden en accenten")
check(Morse.stappen("et").map(\.eenheden) == [1, 3, 3], "morse: e, letterpauze, t")

check(Omzetter.reken("14:35 + 2u50") == "14:35 + 2 u 50 min = 17:25", "tijd: optellen")
check(Omzetter.reken("23:30 + 45 min") == "23:30 + 45 min = 0:15 (volgende dag)", "tijd: over middernacht")
check(Omzetter.reken("9:15 tot 17:30")?.hasPrefix("9:15 tot 17:30 = 8 u 15 min") == true, "tijd: werkuren")
check(Omzetter.reken("22:00 - 6:30")?.hasPrefix("22:00 tot 6:30 = 8 u 30 min") == true, "tijd: nachtdienst")
check(Omzetter.reken("dagen tot 9 okt", nu: zaterdag) == "Nog 13 dagen", "tijd: dagen tot")
check(Omzetter.duur("1,5 uur") == 90, "tijd: anderhalf uur")

check(Herinnering.vind(in: "elke maandag vuilnis buiten", nu: zaterdag)?.herhaal == .wekelijks, "herhaal: elke maandag")
check(Herinnering.vind(in: "elke dag om 8:00 pil", nu: zaterdag)?.herhaal == .dagelijks, "herhaal: elke dag")
check(Herinnering.vind(in: "elke 3 dagen planten water", nu: zaterdag)?.herhaal == .elke(dagen: 3), "herhaal: elke 3 dagen")
check(Herinnering.vind(in: "iedere 2 weken beddengoed", nu: zaterdag)?.herhaal == .elke(dagen: 14), "herhaal: elke 2 weken")
check(Herinnering.vind(in: "elke verjaardag taart", nu: zaterdag) == nil, "herhaal: verjaardag is geen weekdag")
check(Herinnering.vind(in: "morgen om 9:00 tandarts", nu: zaterdag)?.herhaal == nil, "eenmalig blijft eenmalig")

check(Scores.totalen([[10, 5], [3, 20]], spelers: 3) == [13, 25, 0], "score: totalen, nieuwe speler op 0")
check(Scores.stand([13, 25, 0], laagsteWint: false) == [1, 0, 2], "score: hoogste wint")
check(Scores.stand([13, 25, 13], laagsteWint: true) == [0, 2, 1], "score: laagste wint, gelijk op volgorde")

check(Omzetter.reken("15:00 in tokyo")?.hasSuffix("in Tokyo") == true, "tijdzone: 15:00 in tokyo")
check(Omzetter.reken("hoe laat is het in new york?")?.hasPrefix("In New York is het nu") == true, "tijdzone: hoe laat in new york")
check(Omzetter.reken("15:00 in atlantis") == nil, "tijdzone: onbekende stad")
check(Omzetter.klokTekst(Date(timeIntervalSince1970: 0), TimeZone(identifier: "Asia/Tokyo")!) == "9:00", "tijdzone: klok in tokyo")

print("Alle Kniv-checks geslaagd")
