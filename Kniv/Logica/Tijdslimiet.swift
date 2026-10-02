import Foundation

enum Tijdslimiet {
    /// Het antwoord van `werk`, of nil als het langer duurt dan `seconden`; het werk krijgt dan een
    /// stopverzoek. Bewust geen TaskGroup: die wacht aan het eind alsnog op werk dat niet wil stoppen.
    static func binnen<T: Sendable>(_ seconden: Double, _ werk: @escaping @Sendable () async -> T?) async -> T? {
        let eenmaal = Eenmaal()
        return await withCheckedContinuation { (c: CheckedContinuation<T?, Never>) in
            let taak = Task {
                let uit = await werk()
                if eenmaal.eerste() { c.resume(returning: uit) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconden * 1_000_000_000))
                if eenmaal.eerste() {
                    taak.cancel()
                    c.resume(returning: nil)
                }
            }
        }
    }

    /// Waar voor precies één aanroeper; daarna onwaar.
    private final class Eenmaal: @unchecked Sendable {
        private let slot = NSLock()
        private var gebruikt = false
        func eerste() -> Bool {
            slot.lock(); defer { slot.unlock() }
            if gebruikt { return false }
            gebruikt = true
            return true
        }
    }
}
