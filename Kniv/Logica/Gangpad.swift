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
                   "spinazie", "avocado", "champignons", "courgette", "prei", "groente", "fruit", "kiwi", "mango", "gember", "bloemkool"],
        .brood: ["brood", "broodjes", "croissant", "croissants", "stokbrood", "beschuit", "wraps", "pistolets", "bolletjes"],
        .vlees: ["kip", "kipfilet", "gehakt", "vlees", "biefstuk", "worst", "worstjes", "spek", "zalm", "vis", "tonijn", "garnalen", "ham",
                 "shoarma", "hamburger", "hamburgers", "schnitzel", "tofu", "vega"],
        .zuivel: ["melk", "yoghurt", "kwark", "vla", "boter", "roomboter", "room", "slagroom", "eieren", "ei", "karnemelk", "margarine"],
        .kaas: ["kaas", "plakjes", "mozzarella", "feta", "hummus", "salami", "smeerkaas", "beleg", "pindakaas", "hagelslag", "jam", "nutella"],
        .voorraad: ["pasta", "spaghetti", "macaroni", "rijst", "noedels", "bloem", "suiker", "olie", "olijfolie", "azijn", "saus", "pastasaus",
                    "tomatenpuree", "bonen", "mais", "blik", "kruiden", "zout", "peper", "bouillon", "soep", "ketchup", "mayonaise", "mosterd"],
        .ontbijt: ["koffie", "thee", "cruesli", "muesli", "havermout", "cornflakes", "ontbijtkoek", "cacao"],
        .snoep: ["chips", "koek", "koekjes", "snoep", "chocolade", "drop", "nootjes", "popcorn", "stroopwafels"],
        .drinken: ["water", "cola", "fris", "sap", "jus", "bier", "wijn", "limonade", "ranja", "energy", "sportdrank"],
        .diepvries: ["ijs", "diepvries", "pizza", "friet", "patat", "doperwten", "spinazie à la crème", "vissticks"],
        .verzorging: ["shampoo", "tandpasta", "tandenborstel", "deo", "deodorant", "zeep", "douchegel", "scheermesjes", "maandverband",
                      "tampons", "zonnebrand", "paracetamol", "pleisters", "wattenstaafjes"],
        .huishouden: ["wc-papier", "toiletpapier", "keukenrol", "afwasmiddel", "wasmiddel", "vuilniszakken", "sponsjes", "allesreiniger",
                      "batterijen", "aluminiumfolie", "vaatwastabletten", "wasverzachter"],
    ]

    static func van(_ item: String) -> Gangpad {
        let klein = item.lowercased()
        let tokens = Set(klein.components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "-")).inverted))
        // Eerst meerwoordige termen, dan losse woorden; de langste treffer wint (zodat "pindakaas" niet bij "kaas"-woorden sneuvelt).
        var beste: (Gangpad, Int)?
        for (pad, lijst) in woorden {
            for w in lijst where w.contains(" ") ? klein.contains(w) : tokens.contains(w) || tokens.contains(where: { $0.hasSuffix(w) && w.count >= 4 }) {
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
