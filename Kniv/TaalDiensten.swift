import Foundation
import Translation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Stukjes en woordbetekenissen: op de iPhone zelf als dat kan, anders via de Edge Function `taal`.
enum TaalDienst {
    enum Fout: Error {
        case geenInternet, daglimiet, nietIngelogd, mislukt

        var melding: String {
            switch self {
            case .geenInternet: String(localized: "Deze taal heeft internet nodig. Je eerdere stukjes kun je gewoon lezen.")
            case .daglimiet: String(localized: "Vandaag zijn de online stukjes op. Morgen weer, en talen die je iPhone zelf kent gaan gewoon door.")
            case .nietIngelogd: String(localized: "Log in bij Instellingen om deze taal te gebruiken.")
            case .mislukt: String(localized: "Dat lukte even niet. Probeer het nog eens.")
            }
        }
    }

    /// Wat de iPhone zelf kan voor deze taal: tekst maken, vertalen naar het Nederlands, voorlezen.
    static func vermogen(_ code: String) async -> TaalVermogen {
        var tekst = false
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), Denker.beschikbaar {
            tekst = SystemLanguageModel.default.supportedLanguages.contains { $0.languageCode?.identifier == code }
        }
        #endif
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: code), to: Locale.Language(identifier: "nl"))
        let vertalen = status == .installed || status == .supported
        return TaalVermogen(tekstOpToestel: tekst, vertalenOpToestel: vertalen, stem: Voorlezer.stem(voor: code) != nil)
    }

    /// Maakt een stukje en controleert dat het echt in de doeltaal is; zo niet, één nieuwe poging.
    static func nieuwStukje(taal code: String, niveau: String, onderwerp: String, vermogen: TaalVermogen) async throws -> Stukje {
        for _ in 0..<2 {
            let stukje: Stukje?
            switch vermogen.tekstBron {
            case .toestel:
                let instructies = Stukje.instructies(taalNaam: Talen.naam(code, in: Locale(identifier: "nl")), niveau: niveau)
                stukje = await Denker.vraag(instructies, Stukje.prompt(onderwerp: onderwerp)).flatMap(Stukje.ontleed)
            case .online:
                let data = try await vraag(["soort": "stukje", "taal": code, "niveau": niveau, "onderwerp": Stukje.schoon(onderwerp: onderwerp)])
                stukje = Stukje.ontleedJSON(data)
            }
            if let stukje, stukje.isIn(code) { return stukje }
        }
        throw Fout.mislukt
    }

    /// Nederlandse betekenis van een woord in zijn zin, via de functie `taal` (telt mee voor de daglimiet).
    static func betekenis(van woord: String, zin: String, taal code: String) async throws -> String {
        let data = try await vraag(["soort": "woord", "taal": code, "woord": woord, "zin": zin])
        struct Antwoord: Decodable { let betekenis: String? }
        guard let betekenis = (try? JSONDecoder().decode(Antwoord.self, from: data))?.betekenis?
            .trimmingCharacters(in: .whitespacesAndNewlines), !betekenis.isEmpty else { throw Fout.mislukt }
        return betekenis
    }

    /// POST naar de Edge Function `taal`, net als Spraak.verbeter().
    private static func vraag(_ body: [String: String]) async throws -> Data {
        guard let sessie = try? await KnivCloud.client.auth.session else { throw Fout.nietIngelogd }
        var vraag = URLRequest(url: URL(string: "https://ykptlgckqppgxirtndch.supabase.co/functions/v1/taal")!, timeoutInterval: 40)
        vraag.httpMethod = "POST"
        vraag.setValue("Bearer \(sessie.accessToken)", forHTTPHeaderField: "Authorization")
        vraag.setValue(KnivCloud.publishable, forHTTPHeaderField: "apikey")
        vraag.setValue("application/json", forHTTPHeaderField: "Content-Type")
        vraag.httpBody = try JSONEncoder().encode(body)
        let data: Data, antwoord: URLResponse
        do { (data, antwoord) = try await URLSession.shared.data(for: vraag) }
        catch is URLError { throw Fout.geenInternet }
        catch { throw Fout.mislukt }
        switch (antwoord as? HTTPURLResponse)?.statusCode {
        case 200: return data
        case 429: throw Fout.daglimiet
        default: throw Fout.mislukt
        }
    }
}
