import Foundation

/// Checks voor de logica van het mesje Talen (Kniv/Logica/Taal*.swift, Stukje.swift, Woorden.swift).
func talenChecks() {
    check(Stukje(titel: "Bus", tekst: "Ek ry elke oggend met die bus skool toe. Meestal luister ek na musiek en kyk ek by die venster uit.").isIn("af"), "Afrikaans niet afgewezen als Nederlands")
    check(Taalniveau.code(0) == "A1" && Taalniveau.code(8) == "C1" && Taalniveau.code(99) == "C1" && Taalniveau.code(-3) == "A1", "niveaucodes binnen grenzen")
    check(Taalniveau.na(.teMakkelijk, stap: 4) == 5 && Taalniveau.na(.teMoeilijk, stap: 4) == 3 && Taalniveau.na(.precies, stap: 4) == 4, "niveau schuift een halve stap")
    check(Taalniveau.na(.teMakkelijk, stap: 8) == 8 && Taalniveau.na(.teMoeilijk, stap: 0) == 0, "niveau blijft binnen A1…C1")
    check(Taalniveau.startKeuzes.allSatisfy { Taalniveau.code($0.stap) == $0.code } && Taalniveau.startKeuzes.count == 5, "startkeuzes passen bij de codes")

    let nlTalen = Talen.alle(in: Locale(identifier: "nl"))
    check(nlTalen.contains { $0.code == "de" && $0.naam == "Duits" }, "Duits in de lijst")
    check(nlTalen.contains { $0.code == "sw" } && nlTalen.contains { $0.code == "ja" }, "ook kleine en verre talen")
    check(!nlTalen.contains { $0.code == "nl" } && nlTalen.count > 100, "alle talen behalve Nederlands: \(nlTalen.count)")
    check(Talen.zoek("jap", in: nlTalen).map(\.code) == ["ja"], "zoeken op naam")
    check(Talen.zoek("DE", in: nlTalen).first?.code == "de", "zoeken op code gaat voor")
    check(Talen.zoek("  ", in: nlTalen).count == nlTalen.count, "lege zoektekst toont alles")
    check(Talen.naam("de", in: Locale(identifier: "nl")) == "Duits", "naam van een taal")

    let offline = TaalVermogen(tekstOpToestel: true, vertalenOpToestel: true, stem: true)
    check(offline.tekstBron == .toestel && TaalVermogen.niets.tekstBron == .online, "tekstbron volgt het toestel")
    check(TaalVermogen.niets.woordBron(inWoordenlijst: true) == .woordenlijst, "woordenlijst van het stukje gaat voor")
    check(offline.woordBron(inWoordenlijst: false) == .toestel && TaalVermogen.niets.woordBron(inWoordenlijst: false) == .online, "woord: toestel of online")

    check(Stukje.schoon(onderwerp: "  Minecraft\n redstone  ") == "Minecraft redstone", "onderwerp op één regel")
    check(Stukje.schoon(onderwerp: String(repeating: "a", count: 300)).count == 80, "onderwerp ingekort")
    check(Stukje.prompt(onderwerp: " Games\n") == "Onderwerp: Games", "prompt met schoon onderwerp")
    check(Stukje.instructies(taalNaam: "Duits", niveau: "B1").contains("Duits") && Stukje.instructies(taalNaam: "Duits", niveau: "B1").contains("B1"), "instructies noemen taal en niveau")
    let doos = Stukje.ontleed("**Im Bus**\n\nIch fahre jeden Morgen mit dem Bus zur Schule.")
    check(doos?.titel == "Im Bus" && doos?.tekst == "Ich fahre jeden Morgen mit dem Bus zur Schule.", "titel en tekst van het toestelmodel")
    check(Stukje.ontleed("# \"Hallo\"\nZweite Zeile.")?.titel == "Hallo", "kopje en aanhalingstekens van de titel af")
    check(Stukje.ontleed("Alleen een titel") == nil && Stukje.ontleed("") == nil, "zonder tekst geen stukje")
    let js = Stukje.ontleedJSON(Data("```json\n{\"titel\":\"Hola\",\"tekst\":\"Hola, ¿qué tal?\",\"woorden\":{\"Hola\":\"hallo\"}}\n```".utf8))
    check(js?.titel == "Hola" && js?.woorden["hola"] == "hallo", "JSON in codeblok, woorden in kleine letters")
    check(Stukje.ontleedJSON(Data("{\"titel\":\"\",\"tekst\":\"x\"}".utf8)) == nil && Stukje.ontleedJSON(Data("geen json".utf8)) == nil, "lege of kapotte JSON afgewezen")
    check(Stukje.ontleedJSON(Data("{\"titel\":\"T\",\"tekst\":\"x\",\"woorden\":[1,2]}".utf8))?.woorden == [:], "kapotte woordenlijst kost het stukje niet")
    check(Stukje(titel: "Bus", tekst: "Ich fahre jeden Morgen mit dem Bus zur Schule. Meistens höre ich dabei Musik und schaue aus dem Fenster.").isIn("de"), "Duits is Duits")
    check(!Stukje(titel: "Bus", tekst: "Ik ga elke ochtend met de bus naar school. Meestal luister ik dan naar muziek en kijk ik uit het raam.").isIn("de"), "Nederlands antwoord afgewezen")
    check(Stukje(titel: "Safari", tekst: "Ninapenda kusafiri kwa basi kila asubuhi. Ninasikiliza muziki na kuangalia nje ya dirisha.").isIn("sw"), "onbekende taal niet onterecht afgewezen")
    check(Stukje(titel: "Bus", tekst: "I take the bus to school every morning. Usually I listen to music and look out of the window.").isIn("en"), "Engels mag als je Engels leert")

    let klok = "Es ist 5 Uhr, oder?"
    check(Woorden.knip(klok, taal: "de").map(\.tekst) == ["Es", "ist", "Uhr", "oder"], "geen cijfers of leestekens: \(Woorden.knip(klok, taal: "de").map(\.tekst))")
    check(Woorden.knip(klok, taal: "de").allSatisfy { klok[$0.bereik] == $0.tekst }, "bereik wijst naar het woord")
    let ja = Woorden.knip("私は寿司を食べる。", taal: "ja").map(\.tekst)
    check(ja.joined() == "私は寿司を食べる" && ja.contains("寿司"), "Japans zonder spaties geknipt: \(ja)")
    check(Woorden.lezing("寿司", taal: "ja") == "すし", "lezing in hiragana: \(Woorden.lezing("寿司", taal: "ja") ?? "nil")")
    check(Woorden.lezing("Uhr", taal: "de") == nil && Woorden.lezing("すし", taal: "ja") == nil, "geen lezing als die niets toevoegt")
    let twee = "Ich bin müde. Der Bus kommt zu spät."
    check(Woorden.zin(om: twee.range(of: "Bus")!, in: twee) == "Der Bus kommt zu spät.", "zin rond een woord")
    check(Woorden.zin(om: twee.range(of: "müde")!, in: twee) == "Ich bin müde.", "eerste zin")
}
