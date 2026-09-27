import SwiftUI

/// Bij het openen klapt het lemmet uit het handvat; daarna vervaagt het naar de tegels. Kort (±0,9 s) en niet bij "minder beweging".
struct Opening: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var minderBeweging
    @State private var fase = 0          // 0 = dicht, 1 = open, 2 = weg

    func body(content: Content) -> some View {
        ZStack {
            content
                .scaleEffect(fase == 2 ? 1 : 0.96)
                .opacity(fase == 2 ? 1 : 0)
            if fase < 2 {
                ZStack(alignment: .leading) {
                    LemmetVorm()
                        .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 150, height: 40)
                        .rotationEffect(.degrees(fase == 0 ? -178 : 0), anchor: .leading)
                        .offset(x: 112)
                    Capsule().fill(Color.accentColor.gradient).frame(width: 120, height: 50)
                        .overlay(alignment: .trailing) { Circle().fill(.white.opacity(0.85)).frame(width: 10).padding(.trailing, 16) }
                }
                .frame(width: 270, height: 60, alignment: .leading)
                .rotationEffect(.degrees(-30))
                .scaleEffect(fase == 1 ? 1.04 : 1)
                .transition(.opacity.combined(with: .scale(scale: 1.3)))
                .accessibilityHidden(true)
            }
        }
        .task {
            guard !minderBeweging else { fase = 2; return }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { fase = 1 }
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeOut(duration: 0.3)) { fase = 2 }
        }
    }
}
