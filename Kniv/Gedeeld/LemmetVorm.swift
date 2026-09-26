import SwiftUI

/// Het Kniv-lemmet: rechte rug, snede die naar de punt buigt. Gedeeld met de widgets.
struct LemmetVorm: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX * 0.8, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY * 0.8), control: CGPoint(x: r.maxX * 0.97, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX * 0.2, y: r.maxY), control: CGPoint(x: r.maxX * 0.62, y: r.maxY * 1.05))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
