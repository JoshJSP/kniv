import SwiftUI

/// Scrollbare pillen in plaats van een segmented control: past ook met zeven onderdelen, en houdt de keuze in beeld.
struct TabBalk<T: Hashable>: View {
    let tabs: [T]
    @Binding var keuze: T
    let naam: (T) -> String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs, id: \.self) { t in
                        let actief = keuze == t
                        Button { withAnimation(.snappy) { keuze = t } } label: {
                            Text(LocalizedStringKey(naam(t)))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(actief ? Color.white : Color.primary)
                                .background(actief ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(t)
                        .accessibilityAddTraits(actief ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: keuze) { withAnimation(.snappy) { proxy.scrollTo(keuze, anchor: .center) } }
            .sensoryFeedback(.selection, trigger: keuze)
        }
    }
}
