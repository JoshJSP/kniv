import SwiftUI

/// "Sam heeft mijn oplader": na twee weken vraagt Kniv of je hem al terug hebt.
struct UitleenKnop: View {
    let notitie: Notitie
    @State private var gepland = false

    var body: some View {
        if let u = Uitlenen.vind(in: notitie.tekst) {
            Section {
                Button {
                    Meldingen.plan("uitleen.\(notitie.uid)", String(localized: "Heeft \(u.wie) je \(u.wat) al teruggegeven?"),
                                   na: 14 * 86_400)
                    gepland = true
                } label: {
                    Label(gepland ? "Over twee weken vraagt Kniv het je" : "Herinner me eraan om \(u.wat) terug te vragen",
                          systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(gepland)
            }
        }
    }
}
