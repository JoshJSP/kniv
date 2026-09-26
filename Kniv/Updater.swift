import SwiftUI

/// Kijkt in de SideStore-bron of er een nieuwere build is. Installeren zelf kan alleen SideStore;
/// Kniv opent die met sidestore://install, zodat één tik genoeg is.
enum Updater {
    struct Bron: Decodable {
        struct App: Decodable { let versions: [Versie] }
        struct Versie: Decodable { let version: String; let buildVersion: String; let downloadURL: String }
        let apps: [App]
    }

    struct Update: Equatable {
        let versie: String
        let installeer: URL
    }

    static func zoek() async -> Update? {
        var vraag = URLRequest(url: URL(string: "https://raw.githubusercontent.com/JoshJSP/kniv-releases/main/apps.json?t=\(Int(Date().timeIntervalSince1970))")!)
        vraag.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: vraag),
              let nieuwste = (try? JSONDecoder().decode(Bron.self, from: data))?.apps.first?.versions.first,
              let build = Int(nieuwste.buildVersion),
              build > Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 else { return nil }
        var link = URLComponents(string: "sidestore://install")!
        link.queryItems = [URLQueryItem(name: "url", value: nieuwste.downloadURL)]
        return link.url.map { Update(versie: nieuwste.version, installeer: $0) }
    }
}

struct UpdateBalk: View {
    let update: Updater.Update
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(update.installeer) } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update beschikbaar").font(.headline)
                    Text("Versie \(update.versie). Tik om te installeren via SideStore.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .glas(20)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
