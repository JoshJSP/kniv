import SwiftUI
import Translation

/// Slaapadvies: bedtijden die uitkomen op het eind van een slaapcyclus.
struct SlaapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wakker = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 7, minute: 30), matchingPolicy: .nextTime)!
    @State private var gepland: Date?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Ik wil wakker worden om", selection: $wakker, displayedComponents: .hourAndMinute)
                    ForEach(Slaap.bedtijden(wakker: wakker), id: \.cycli) { b in
                        Button {
                            gepland = b.tijd
                            Meldingen.plan("slaap", String(localized: "Over een kwartier naar bed voor \(b.cycli) slaapcycli"),
                                           na: b.tijd.addingTimeInterval(-15 * 60).timeIntervalSinceNow)
                        } label: {
                            HStack {
                                Text(b.tijd, format: .dateTime.hour().minute()).font(.title2.monospacedDigit().weight(.semibold))
                                Spacer()
                                Text("\(b.cycli) cycli · \(Omzetter.mooi(Double(b.cycli) * 1.5)) uur")
                                    .foregroundStyle(b.cycli == 5 ? Color.accentColor : .secondary)
                                if gepland == b.tijd { Image(systemName: "bell.fill").foregroundStyle(Color.accentColor) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Ga slapen om")
                } footer: {
                    Text("Tik op een tijd voor een seintje een kwartier van tevoren. Kniv rekent met cycli van 90 minuten en een kwartier om in slaap te vallen.")
                }
                Section("Ga je nu slapen? Word wakker om") {
                    ForEach(Slaap.wektijden(vanaf: Date()), id: \.cycli) { w in
                        HStack {
                            Text(w.tijd, format: .dateTime.hour().minute()).font(.title3.monospacedDigit())
                            Spacer()
                            Text("\(w.cycli) cycli").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Slaapadvies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
        }
    }
}

/// Knop die Apple's vertaalvenster opent (offline, gratis).
struct VertaalKnop: View {
    let tekst: String
    @State private var toon = false

    var body: some View {
        Button { toon = true } label: { Label("Vertaal", systemImage: "translate") }
            .translationPresentation(isPresented: $toon, text: tekst)
    }
}
