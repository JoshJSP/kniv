import SwiftUI

/// Taal van Kniv kiezen: systeem, Nederlands of Engels. iOS leest de taal bij het opstarten,
/// dus na een wissel open je Kniv één keer opnieuw.
struct TaalKeuze: View {
    @AppStorage("taal") private var taal = ""          // "" = volg iPhone
    @State private var herstart = false

    var body: some View {
        Picker(selection: Binding(get: { taal }, set: zet)) {
            Text("Zoals mijn iPhone").tag("")
            Text("Nederlands").tag("nl")
            Text("English").tag("en")
        } label: {
            Label("Taal", systemImage: "globe")
        }
        .alert("Open Kniv opnieuw", isPresented: $herstart) {
            Button("Oké", role: .cancel) {}
        } message: {
            Text("Sluit Kniv (veeg hem weg in de appkiezer) en open hem opnieuw. Dan spreekt hij je nieuwe taal.")
        }
    }

    private func zet(_ nieuw: String) {
        guard nieuw != taal else { return }
        taal = nieuw
        if nieuw.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([nieuw], forKey: "AppleLanguages")
        }
        herstart = true
    }
}
