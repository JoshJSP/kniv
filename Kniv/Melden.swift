import SwiftUI
import UIKit

extension Notification.Name {
    static let geschud = Notification.Name("kniv.geschud")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .geschud, object: self) }
        super.motionEnded(motion, with: event)
    }
}

/// Schudden = fout melden, alleen in de ontwikkelaarsmodus (5× op de versie tikken) en nooit in het dobbelmesje.
struct MeldSchudden: ViewModifier {
    @AppStorage("ontwikkelaar") private var ontwikkelaar = false
    @State private var screenshot: UIImage?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .geschud)) { melding in
                guard ontwikkelaar, !AppStatus.shared.inDobbelmesje, screenshot == nil, let venster = melding.object as? UIWindow else { return }
                screenshot = UIGraphicsImageRenderer(bounds: venster.bounds).image { _ in
                    venster.drawHierarchy(in: venster.bounds, afterScreenUpdates: false)
                }
            }
            .sheet(isPresented: Binding(get: { screenshot != nil }, set: { if !$0 { screenshot = nil } })) {
                if let screenshot { MeldView(screenshot: screenshot) }
            }
    }
}

struct MeldView: View {
    let screenshot: UIImage
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var wat = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Wat ging er mis?", text: $wat, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    Image(uiImage: screenshot).resizable().scaledToFit().frame(maxHeight: 260).frame(maxWidth: .infinity)
                } footer: {
                    Text("De screenshot staat straks op je klembord. Plak hem in het issue.")
                }
            }
            .navigationTitle("Fout melden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Meld", action: meld).disabled(wat.isEmpty) }
            }
        }
    }

    private func meld() {
        UIPasteboard.general.image = screenshot
        let versie = VersieInfo.huidig.map { "\($0.mesnaam) \($0.versie)" } ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let tekst = "\(wat)\n\n---\nKniv \(versie) (build \(build)) · iOS \(UIDevice.current.systemVersion)\n\n_Plak hier de screenshot._"
        var url = URLComponents(string: "https://github.com/JoshJSP/kniv/issues/new")!
        url.queryItems = [URLQueryItem(name: "title", value: String(wat.prefix(70))), URLQueryItem(name: "body", value: tekst),
                          URLQueryItem(name: "labels", value: "melding")]
        if let u = url.url { openURL(u) }
        dismiss()
    }
}
