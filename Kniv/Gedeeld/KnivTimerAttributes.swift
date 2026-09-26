import ActivityKit
import Foundation

/// Gedeeld door de app en de widget-extensie: een lopende timer op het vergrendelscherm.
struct KnivTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var eind: Date
        var duur: TimeInterval
    }

    var naam: String
}
