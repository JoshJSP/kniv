import Foundation

/// Zet boodschappen in de volgorde waarin je door een Nederlandse supermarkt loopt,
/// zodat je één rondje hoeft te lopen.
enum Gangpad: Int, CaseIterable {
    case groente, brood, vlees, zuivel, kaas, voorraad, ontbijt, snoep, drinken, diepvries, verzorging, huishouden, overig

    var naam: String {
        switch self {
        case .groente: "Groente & fruit"
        case .brood: "Brood"
        case .vlees: "Vlees & vis"
        case .zuivel: "Zuivel & eieren"
        case .kaas: "Kaas & beleg"
        case .voorraad: "Pasta, rijst & blik"
        case .ontbijt: "Ontbijt & koffie"
        case .snoep: "Koek, snoep & chips"
        case .drinken: "Drinken"
        case .diepvries: "Diepvries"
        case .verzorging: "Verzorging"
        case .huishouden: "Huishouden"
        case .overig: "Overig"
        }
    }

    static let woorden: [Gangpad: [String]] = [
        .groente: ["appel", "appels", "banaan", "bananen", "peer", "sinaasappel", "citroen", "druiven", "aardbeien", "tomaat", "tomaten",
                   "komkommer", "sla", "paprika", "ui", "uien", "knoflook", "wortel", "wortels", "aardappel", "aardappelen", "broccoli",
                   "spinazie", "avocado", "champignons", "courgette", "prei", "groente", "fruit", "kiwi", "mango", "gember", "bloemkool",
                   "peren", "aardbei", "rucola", "sperziebonen", "snijbonen", "boontjes", "kool", "spitskool", "rodekool", "zuurkool",
                   "andijvie", "boerenkool", "radijs", "biet", "bieten", "pompoen", "aubergine", "asperges", "lente-ui", "bosui",
                   "basilicum", "peterselie", "koriander", "munt", "limoen", "meloen", "ananas", "framboos", "frambozen", "blauwe bessen",
                   "bessen", "pruimen", "perzik", "nectarine", "mandarijn", "mandarijnen", "taugé", "maïs aan de kolf"],
        .brood: ["brood", "broodjes", "croissant", "croissants", "stokbrood", "beschuit", "wraps", "pistolets", "bolletjes",
                 "krentenbollen", "afbakbroodjes", "pita", "tortilla", "tortilla's", "naan", "bagels", "toast"],
        .vlees: ["kip", "kipfilet", "gehakt", "vlees", "biefstuk", "worst", "worstjes", "spek", "zalm", "vis", "tonijn", "garnalen", "ham",
                 "shoarma", "hamburger", "hamburgers", "schnitzel", "tofu", "vega", "zalmfilet", "kabeljauw", "kipdijen", "drumsticks",
                 "rookworst", "slavink", "speklapjes", "rundvlees", "varkensvlees", "lamsvlees", "spareribs", "kipkerrie", "tempeh"],
        .zuivel: ["melk", "yoghurt", "kwark", "vla", "boter", "roomboter", "room", "slagroom", "eieren", "ei", "karnemelk", "margarine",
                  "skyr", "crème fraîche", "zure room", "kookroom", "havermelk", "sojamelk", "pudding", "toetjes", "toetje"],
        .kaas: ["kaas", "plakjes", "mozzarella", "feta", "hummus", "salami", "smeerkaas", "beleg", "pindakaas", "hagelslag", "jam", "nutella",
                "chocopasta", "chocoladepasta", "vlokken", "appelstroop", "honing", "leverworst", "filet americain", "kipfilet beleg",
                "parmezaan", "geitenkaas", "brie", "roomkaas", "boursin"],
        .voorraad: ["pasta", "spaghetti", "macaroni", "rijst", "noedels", "bloem", "suiker", "olie", "olijfolie", "azijn", "saus", "pastasaus",
                    "tomatenpuree", "bonen", "mais", "blik", "kruiden", "zout", "peper", "bouillon", "soep", "ketchup", "mayonaise", "mosterd",
                    "lasagne", "penne", "tagliatelle", "couscous", "bulgur", "quinoa", "linzen", "kikkererwten", "tomatenblokjes",
                    "passata", "pesto", "sambal", "sojasaus", "kokosmelk", "curry", "taco", "tacos", "bakpoeder", "gist", "paneermeel",
                    "mie", "wokolie", "zonnebloemolie", "frituurolie", "pindasaus", "satésaus", "fritessaus"],
        .ontbijt: ["koffie", "thee", "cruesli", "muesli", "havermout", "cornflakes", "ontbijtkoek", "cacao", "koffiebonen", "koffiepads",
                   "koffiecups", "granola", "rijstwafels", "ontbijtgranen", "melkpoeder", "suikerklontjes"],
        .snoep: ["chips", "koek", "koekjes", "snoep", "chocolade", "drop", "nootjes", "popcorn", "stroopwafels", "stroopwafel",
                 "crackers", "toastjes", "zoutjes", "borrelnootjes", "pinda's", "pinda", "kauwgom", "pepermunt", "repen", "reep",
                 "biscuit", "biscuits", "tompouce", "gebak", "taart", "muffins", "wafels", "chocoladereep"],
        .drinken: ["water", "cola", "fris", "sap", "jus", "bier", "wijn", "limonade", "ranja", "energy", "sportdrank", "frisdrank",
                   "ijsthee", "energydrink", "spa", "sinas", "cassis", "tonic", "radler", "prosecco", "smoothie", "siroop"],
        .diepvries: ["ijs", "diepvries", "pizza", "friet", "patat", "doperwten", "spinazie à la crème", "vissticks", "ijsblokjes",
                     "frikandellen", "kroketten", "bitterballen", "loempia", "loempia's", "kipnuggets", "magnum", "ijsjes"],
        .verzorging: ["shampoo", "tandpasta", "tandenborstel", "deo", "deodorant", "zeep", "douchegel", "scheermesjes", "maandverband",
                      "tampons", "zonnebrand", "paracetamol", "pleisters", "wattenstaafjes", "mondwater", "babyolie", "bodylotion", "crème",
                      "gezichtscrème", "conditioner", "haargel", "scheerschuim", "wattenschijfjes", "luiers", "billendoekjes",
                      "ibuprofen", "lenzenvloeistof", "flosdraad", "lippenbalsem", "nagellak"],
        .huishouden: ["wc-papier", "toiletpapier", "keukenrol", "afwasmiddel", "wasmiddel", "vuilniszakken", "sponsjes", "allesreiniger",
                      "batterijen", "aluminiumfolie", "vaatwastabletten", "wasverzachter", "wc papier", "keukenpapier", "vershoudfolie",
                      "bakpapier", "wc-blokjes", "wc-eend", "schoonmaakazijn", "glasreiniger", "afwasborstel", "theedoeken",
                      "kattenvoer", "hondenvoer", "kattenbakvulling", "lampen", "kaarsen", "lucifers", "vriezerzakjes", "boterhamzakjes"],
    ]

    /// Kleine letters, zonder accenten ("maïs" = "mais", "crème" = "creme").
    private static func plat(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl"))
    }

    /// Het woord zelf en zonder verkleinwoord of meervoud: appeltjes → appel, broodje → brood, citroenen → citroen.
    static func vormen(_ woord: String) -> [String] {
        var uit = [woord]
        for uitgang in ["tjes", "etjes", "jes", "tje", "je", "en", "s", "'s"] where woord.hasSuffix(uitgang) && woord.count - uitgang.count >= 3 {
            uit.append(String(woord.dropLast(uitgang.count)))
        }
        return uit
    }

    private static let platteWoorden: [(Gangpad, [String])] = Gangpad.allCases.map { pad in (pad, (woorden[pad] ?? []).map(plat)) }

    static func van(_ item: String) -> Gangpad {
        let klein = plat(item)
        let tokens = klein.components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "-'")).inverted).filter { !$0.isEmpty }
        if tokens.contains(where: { $0.hasPrefix("diepvries") }) { return .diepvries }
        let alle = Set(tokens.flatMap { vormen($0) })
        // Eerst meerwoordige termen, dan losse woorden; de langste treffer wint (zodat "pindakaas" niet bij "kaas"-woorden sneuvelt).
        // Een woord mag ook het eind van een samenstelling zijn (chocoladevla, roomijs), mits er genoeg voor staat.
        // Vaste volgorde (allCases), anders wisselde de uitkomst bij gelijke lengte per keer dat de app opende.
        var beste: (Gangpad, Int)?
        for (pad, lijst) in platteWoorden {
            for w in lijst where w.contains(" ")
                ? klein.contains(w)
                : alle.contains(w) || alle.contains(where: { $0.hasSuffix(w) && $0.count - w.count >= (w.count >= 4 ? 1 : 3) }) {
                if w.count > (beste?.1 ?? 0) { beste = (pad, w.count) }
            }
        }
        return beste?.0 ?? .overig
    }

    /// Groepeert in looproute-volgorde; binnen een gangpad blijft jouw volgorde staan.
    static func route<T>(_ items: [T], tekst: (T) -> String) -> [(Gangpad, [T])] {
        let groepen = Dictionary(grouping: items) { van(tekst($0)) }
        return Gangpad.allCases.compactMap { pad in groepen[pad].map { (pad, $0) } }
    }
}
