import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let rood = Color(red: 0.84, green: 0.17, blue: 0.12)

@main
struct KnivWidgetBundle: WidgetBundle {
    var body: some Widget {
        SnelWidget()
        InsprekenControl()
        FotoControl()
        TypenControl()
        KnivLiveActivity()
    }
}

private func link(_ actie: String) -> URL { URL(string: "kniv://\(actie)")! }

// MARK: snelknoppen op beginscherm en vergrendelscherm

struct LeegProvider: TimelineProvider {
    struct Moment: TimelineEntry { let date: Date }
    func placeholder(in context: Context) -> Moment { Moment(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Moment) -> Void) { completion(Moment(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Moment>) -> Void) {
        completion(Timeline(entries: [Moment(date: .now)], policy: .never))
    }
}

struct SnelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "kniv.snel", provider: LeegProvider()) { _ in SnelWidgetView() }
            .configurationDisplayName("Kniv vastleggen")
            .description("Leg met één tik iets vast: typen, inspreken, foto of lijstje.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct SnelWidgetView: View {
    @Environment(\.widgetFamily) private var familie

    private let knoppen = [("tekst", "square.and.pencil", "Typ"), ("inspreken", "mic.fill", "Spreek"),
                           ("foto", "camera.fill", "Foto"), ("lijst", "checklist", "Lijst")]

    var body: some View {
        switch familie {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.title2)
            }
            .widgetURL(link("inspreken"))
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            HStack {
                LemmetVorm().frame(width: 22, height: 8).rotationEffect(.degrees(-35))
                VStack(alignment: .leading) {
                    Text("Kniv").font(.headline)
                    Text("Leg iets vast").font(.caption)
                }
            }
            .widgetURL(link("inspreken"))
            .containerBackground(.clear, for: .widget)
        case .systemMedium:
            HStack(spacing: 10) { ForEach(knoppen, id: \.0) { knop($0, groot: true) } }
                .containerBackground(.fill.tertiary, for: .widget)
        default:
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow { knop(knoppen[0], groot: false); knop(knoppen[1], groot: false) }
                GridRow { knop(knoppen[2], groot: false); knop(knoppen[3], groot: false) }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private func knop(_ k: (String, String, String), groot: Bool) -> some View {
        Link(destination: link(k.0)) {
            VStack(spacing: 4) {
                Image(systemName: k.1).font(groot ? .title2 : .title3)
                if groot { Text(LocalizedStringKey(k.2)).font(.caption2) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(rood)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: Control Center en vergrendelscherm-knoppen

private func knivControl(_ kind: String, _ naam: String, _ icoon: String, _ actie: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: kind) {
        ControlWidgetButton(action: OpenURLIntent(link(actie))) {
            Label(naam, systemImage: icoon)
        }
    }
    .displayName(LocalizedStringResource(stringLiteral: naam))
}

struct InsprekenControl: ControlWidget {
    var body: some ControlWidgetConfiguration { knivControl("kniv.inspreken", "Kniv: inspreken", "mic.fill", "inspreken") }
}

struct FotoControl: ControlWidget {
    var body: some ControlWidgetConfiguration { knivControl("kniv.foto", "Kniv: foto", "camera.fill", "foto") }
}

struct TypenControl: ControlWidget {
    var body: some ControlWidgetConfiguration { knivControl("kniv.tekst", "Kniv: typen", "square.and.pencil", "tekst") }
}

// MARK: Live Activity voor timers

struct KnivLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KnivTimerAttributes.self) { ctx in
            HStack(spacing: 16) {
                MiniLemmet()
                VStack(alignment: .leading, spacing: 4) {
                    Text(ctx.attributes.naam).font(.headline)
                    ProgressView(timerInterval: bereik(ctx.state), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(rood)
                }
                Text(timerInterval: bereik(ctx.state), countsDown: true)
                    .font(.system(size: 34, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
            }
            .padding(18)
            .activityBackgroundTint(Color(.systemBackground).opacity(0.7))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { MiniLemmet().padding(.leading, 6) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: bereik(ctx.state), countsDown: true)
                        .font(.title2.monospacedDigit()).foregroundStyle(rood).frame(width: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: bereik(ctx.state), countsDown: true) { Text(ctx.attributes.naam) } currentValueLabel: { EmptyView() }
                        .tint(rood)
                }
            } compactLeading: {
                MiniLemmet().frame(width: 22)
            } compactTrailing: {
                Text(timerInterval: bereik(ctx.state), countsDown: true)
                    .monospacedDigit().foregroundStyle(rood).frame(width: 46)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(rood)
            }
        }
    }

    private func bereik(_ s: KnivTimerAttributes.ContentState) -> ClosedRange<Date> {
        s.eind.addingTimeInterval(-s.duur)...s.eind
    }
}

struct MiniLemmet: View {
    var body: some View {
        ZStack(alignment: .leading) {
            LemmetVorm().fill(Color(white: 0.85)).frame(width: 26, height: 8).offset(x: 12).rotationEffect(.degrees(-30), anchor: .leading)
            Capsule().fill(rood).frame(width: 18, height: 10)
        }
        .frame(width: 40, height: 24)
        .accessibilityHidden(true)
    }
}
