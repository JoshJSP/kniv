import Contacts
import EventKit
import SwiftUI

/// Kniv ziet wat je bedoelt: een afspraak, iemand om te bellen, een adres, een nummer of een link.
struct SlimmeKnoppen: View {
    let notitie: Notitie
    @Environment(\.openURL) private var openURL
    @State private var inAgenda = false
    @State private var contact: (naam: String, nummer: String)?

    private var tekst: String { notitie.zoekTekst }

    private var gevonden: (adressen: [String], nummers: [String], links: [URL]) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.link.rawValue) else { return ([], [], []) }
        var a: [String] = [], n: [String] = [], l: [URL] = []
        for m in detector.matches(in: tekst, range: NSRange(tekst.startIndex..., in: tekst)) {
            switch m.resultType {
            case .address: if let r = Range(m.range, in: tekst) { a.append(String(tekst[r])) }
            case .phoneNumber: if let p = m.phoneNumber { n.append(p) }
            case .link: if let u = m.url, u.scheme?.hasPrefix("http") == true { l.append(u) }
            default: break
            }
        }
        return (a, n, l)
    }

    /// "oma bellen", "bel Sam", "Lisa appen" → de naam om in je contacten te zoeken.
    private var belNaam: String? {
        let m = Herinnering.eersteMatch(#"(?i)\b(?:bel|bellen|app|appen)\s+(\p{L}+)|(\p{L}+)\s+(?:bellen|appen)\b"#, in: tekst)
        let naam = [m?[1], m?[2]].compactMap { $0 }.first { !$0.isEmpty }
        return naam.flatMap { ["morgen", "even", "nog", "vandaag", "terug"].contains($0.lowercased()) ? nil : $0 }
    }

    var body: some View {
        let g = gevonden
        let moment = Herinnering.vind(in: tekst, nu: notitie.gemaakt)
        if moment?.heeftTijd == true || !g.adressen.isEmpty || !g.nummers.isEmpty || !g.links.isEmpty || belNaam != nil {
            Section("Snel doen") {
                if let moment, moment.heeftTijd {
                    Button { Task { inAgenda = await zetInAgenda(moment.dag) } } label: {
                        Label(inAgenda ? "Staat in je agenda" : "Zet in agenda (\(moment.label))", systemImage: "calendar.badge.plus")
                    }
                    .disabled(inAgenda)
                }
                if let contact {
                    Button { bel(contact.nummer) } label: { Label("Bel \(contact.naam)", systemImage: "phone") }
                }
                ForEach(g.nummers.prefix(2), id: \.self) { nummer in
                    Button { bel(nummer) } label: { Label("Bel \(nummer)", systemImage: "phone") }
                }
                ForEach(g.adressen.prefix(2), id: \.self) { adres in
                    Button {
                        var u = URLComponents(string: "maps://")!
                        u.queryItems = [URLQueryItem(name: "daddr", value: adres)]
                        if let url = u.url { openURL(url) }
                    } label: { Label("Route naar \(adres)", systemImage: "map") }
                }
                ForEach(g.links.prefix(2), id: \.self) { url in
                    Button { openURL(url) } label: { Label(url.host() ?? url.absoluteString, systemImage: "safari") }
                }
            }
            .task(id: belNaam) { contact = await zoekContact(belNaam) }
        }
    }

    private func bel(_ nummer: String) {
        let schoon = nummer.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel:\(schoon)") { openURL(url) }
    }

    private func zetInAgenda(_ start: Date) async -> Bool {
        let store = EKEventStore()
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return false }
        let e = EKEvent(eventStore: store)
        e.title = notitie.titel
        e.startDate = start
        e.endDate = start.addingTimeInterval(3600)
        e.calendar = store.defaultCalendarForNewEvents
        e.addAlarm(EKAlarm(relativeOffset: -30 * 60))
        return (try? store.save(e, span: .thisEvent)) != nil
    }

    private func zoekContact(_ naam: String?) async -> (naam: String, nummer: String)? {
        guard let naam, (try? await CNContactStore().requestAccess(for: .contacts)) == true else { return nil }
        let sleutels = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let gevonden = (try? CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matchingName: naam), keysToFetch: sleutels)) ?? []
        guard let c = gevonden.first(where: { !$0.phoneNumbers.isEmpty }), let nummer = c.phoneNumbers.first?.value.stringValue else { return nil }
        let volledig = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return (c.nickname.isEmpty ? (volledig.isEmpty ? naam : volledig) : c.nickname, nummer)
    }
}
