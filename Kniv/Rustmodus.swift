import SwiftUI

/// 's Avonds (instelbaar) donker en rustig; plekmeldingen zwijgen dan.
struct Rustmodus: ViewModifier {
    @AppStorage("rust") private var aan = false
    @AppStorage("rustVanaf") private var vanaf = 22
    @AppStorage("rustTot") private var tot = 7
    @Environment(\.scenePhase) private var fase
    @State private var actief = false

    static func nu(_ datum: Date = Date()) -> Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: "rust") else { return false }
        let vanaf = d.object(forKey: "rustVanaf") as? Int ?? 22
        let tot = d.object(forKey: "rustTot") as? Int ?? 7
        let uur = Calendar.current.component(.hour, from: datum)
        return uur >= vanaf || uur < tot
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(actief ? .dark : nil)
            .onAppear { actief = Self.nu() }
            .onChange(of: fase) { actief = Self.nu() }
            .onChange(of: aan) { actief = Self.nu() }
            .onChange(of: vanaf) { actief = Self.nu() }
            .onChange(of: tot) { actief = Self.nu() }
    }
}
