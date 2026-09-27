import CoreLocation
import SwiftData
import SwiftUI
import UserNotifications

// MARK: Weer (open-meteo, gratis en zonder sleutel)

enum WeerDienst {
    private static let d = UserDefaults.standard

    /// Laatste advies, hooguit een uur oud.
    static var advies: String? {
        guard let t = d.object(forKey: "weer.tijd") as? Date, Date().timeIntervalSince(t) < 3600 else { return nil }
        return d.string(forKey: "weer.advies")
    }

    @MainActor static func ververs() async {
        if let t = d.object(forKey: "weer.tijd") as? Date, Date().timeIntervalSince(t) < 1800 { return }
        let thuis = ((try? KnivOpslag.container.mainContext.fetch(FetchDescriptor<Plek>())) ?? []).first { $0.soort == "thuis" }
        guard let plek = CLLocationManager().location?.coordinate
                ?? thuis.map({ CLLocationCoordinate2D(latitude: $0.breedte, longitude: $0.lengte) }) else { return }
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(plek.latitude)&longitude=\(plek.longitude)&hourly=precipitation_probability,precipitation,temperature_2m&forecast_hours=12&timezone=auto")!
        struct Antwoord: Decodable {
            struct Uren: Decodable { let time: [String]; let precipitation_probability: [Int?]; let precipitation: [Double?]; let temperature_2m: [Double?] }
            let hourly: Uren
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let a = try? JSONDecoder().decode(Antwoord.self, from: data) else { return }
        let uren = a.hourly.time.indices.map { i in
            Weer.Uur(uur: Int(a.hourly.time[i].suffix(5).prefix(2)) ?? 0, kans: a.hourly.precipitation_probability[i] ?? 0,
                     mm: a.hourly.precipitation[i] ?? 0, temp: a.hourly.temperature_2m[i] ?? 15)
        }
        d.set(Weer.advies(uren), forKey: "weer.advies")
        d.set(Date(), forKey: "weer.tijd")
    }
}

// MARK: Tijdcapsule: een notitie verzegelen tot een datum

struct TijdcapsuleSectie: View {
    @Bindable var notitie: Notitie
    @State private var datum = Calendar.current.date(byAdding: .month, value: 6, to: Date())!

    var body: some View {
        Section {
            if let tot = notitie.verzegeldTot, tot > Date() {
                Label("Verzegeld tot \(tot.formatted(date: .long, time: .omitted))", systemImage: "lock.fill")
            } else {
                DatePicker("Opent op", selection: $datum, in: Date().addingTimeInterval(86_400)..., displayedComponents: .date)
                Button {
                    notitie.verzegeldTot = datum
                    notitie.gewijzigd = Date()
                    Meldingen.plan("capsule.\(notitie.uid)", String(localized: "Je tijdcapsule is open: \(notitie.titel)"),
                                   na: datum.timeIntervalSinceNow)
                } label: { Label("Verzegel als tijdcapsule", systemImage: "hourglass") }
            }
        } header: {
            Text("Tijdcapsule")
        } footer: {
            Text("Schrijf iets voor later. Tot die dag zie je alleen een slotje, ook niet in zoeken.")
        }
    }
}

/// Wat je ziet als je een nog verzegelde notitie opent.
struct VerzegeldView: View {
    let tot: Date

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "hourglass").font(.system(size: 60, weight: .light)).foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse)
            Text("Nog even geduld").font(.title.bold())
            Text("Deze tijdcapsule opent \(tot.formatted(.relative(presentation: .named))).")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KnivAchtergrond())
    }
}

// MARK: Verjaardagen: elk jaar een seintje

struct VerjaardagKnop: View {
    let notitie: Notitie
    @State private var gedaan = false

    var body: some View {
        if let v = Verjaardag.vind(in: notitie.zoekTekst) {
            Section {
                Button {
                    let inhoud = UNMutableNotificationContent()
                    inhoud.title = String(localized: "Verjaardag")
                    inhoud.body = notitie.titel
                    inhoud.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(month: v.maand, day: v.dag, hour: 9), repeats: true)
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                        guard ok else { return }
                        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "jarig.\(notitie.uid)", content: inhoud, trigger: trigger))
                    }
                    gedaan = true
                } label: {
                    Label(gedaan ? "Elk jaar op \(v.dag)-\(v.maand) een seintje" : "Elk jaar herinneren", systemImage: "gift")
                }
                .disabled(gedaan)
            }
        }
    }
}
