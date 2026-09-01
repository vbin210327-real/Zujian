import SwiftUI
import WidgetKit

struct ZujianWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ZujianWidgetSnapshot
}

struct ZujianWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ZujianWidgetEntry {
        ZujianWidgetEntry(date: Date(), snapshot: .previewResting)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ZujianWidgetEntry) -> Void
    ) {
        let snapshot = context.isPreview
            ? ZujianWidgetSnapshot.previewResting
            : ZujianWidgetStore.load()
        completion(ZujianWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<ZujianWidgetEntry>) -> Void
    ) {
        let now = Date()
        let snapshot = ZujianWidgetStore.load(at: now)
        var entries = [ZujianWidgetEntry(date: now, snapshot: snapshot)]

        if snapshot.phase == .resting,
           let restEndDate = snapshot.restEndDate,
           restEndDate > now {
            entries.append(
                ZujianWidgetEntry(
                    date: restEndDate,
                    snapshot: snapshot.resolved(at: restEndDate)
                )
            )
        }

        let nextRefresh = [snapshot.restEndDate, snapshot.automaticRefreshDate]
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
        let policy: TimelineReloadPolicy = nextRefresh.map(TimelineReloadPolicy.after)
            ?? .after(now.addingTimeInterval(6 * 60 * 60))

        completion(Timeline(entries: entries, policy: policy))
    }
}

struct ZujianStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ZujianWidgetStore.widgetKind,
            provider: ZujianWidgetProvider()
        ) { entry in
            ZujianWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("组间")
        .description("在表盘和智能叠放中查看当前训练节奏。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        .containerBackgroundRemovable(false)
    }
}

@main
struct ZujianWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ZujianStatusWidget()
    }
}

private struct ZujianWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: ZujianWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularStatusView(snapshot: entry.snapshot, date: entry.date)
                .containerBackground(for: .widget) {
                    Color.zujianNight
                }
        case .accessoryRectangular:
            RectangularStatusView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.20, blue: 0.22),
                            Color(red: 0.11, green: 0.11, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        default:
            RectangularStatusView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.20, blue: 0.22),
                            Color(red: 0.11, green: 0.11, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
    }
}

private struct CircularStatusView: View {
    let snapshot: ZujianWidgetSnapshot
    let date: Date

    var body: some View {
        ZStack {
            if let restInterval {
                ProgressView(timerInterval: restInterval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    if let endDate = snapshot.restEndDate {
                        Text(endDate, style: .timer)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                    }
                }
                .progressViewStyle(.circular)
                .tint(.zujianMistBlue)
            } else {
                circularContent
            }
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var restInterval: ClosedRange<Date>? {
        guard
            snapshot.phase == .resting,
            let restEndDate = snapshot.restEndDate,
            restEndDate > date
        else { return nil }

        let start = min(snapshot.restStartedAt ?? date, date)
        return start...restEndDate
    }

    @ViewBuilder
    private var circularContent: some View {
        switch snapshot.phase {
        case .active:
            VStack(spacing: -1) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.zujianMistBlue)
                Text("\(snapshot.setNumber)")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.zujianMistBlue)
        default:
            VStack(spacing: -3) {
                Image(snapshot.petImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 45, height: 31)
                    // Widget mascot assets are rendered on black scene canvases.
                    // Screen blending lets the system's circular material remain
                    // the only visible background instead of exposing that canvas.
                    .blendMode(.screen)
                    // Crop away the scene padding visually so the mascot remains
                    // legible at complication size without changing the source art.
                    .scaleEffect(1.32)
                    // The subject sits low inside the source canvas, so align its
                    // visual center rather than the rectangular image bounds.
                    .offset(y: snapshot.phase == .waiting ? -3 : -4)
                    .accessibilityHidden(true)
                if snapshot.phase == .waiting {
                    Text("\(snapshot.setNumber)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
    }

    private var accessibilityLabel: String {
        switch snapshot.phase {
        case .ready: return "组间，点按打开"
        case .waiting: return "等待第 \(snapshot.setNumber) 组"
        case .active: return "第 \(snapshot.setNumber) 组训练中"
        case .resting: return "休息倒计时"
        case .paused: return "训练已暂停"
        case .finished: return "训练完成，共 \(snapshot.completedSetCount) 组"
        }
    }
}

private struct RectangularStatusView: View {
    let snapshot: ZujianWidgetSnapshot

    var body: some View {
        cardContent
            .accessibilityElement(children: .combine)
    }

    private var cardContent: some View {
        HStack(spacing: 7) {
            Image(snapshot.petImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 57, height: 55)
                .blendMode(.screen)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(eyebrowColor)
                        .lineLimit(1)
                }

                mainValue
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let footnote {
                    Text(footnote)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.zujianQuietSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var eyebrow: String? {
        switch snapshot.phase {
        case .ready: return "组间"
        case .waiting: return "等待动作"
        case .active: return "训练中"
        case .resting:
            return snapshot.completedSetCount > 0
                ? "第 \(snapshot.completedSetCount) 组完成"
                : "休息中"
        case .paused: return "已暂停"
        case .finished: return "训练完成"
        }
    }

    private var eyebrowColor: Color {
        snapshot.phase == .ready ? .zujianMistBlue : .zujianQuietSecondary
    }

    @ViewBuilder
    private var mainValue: some View {
        switch snapshot.phase {
        case .ready:
            Text(restDurationLabel)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.zujianMoonlight)
        case .waiting:
            Text("第 \(snapshot.setNumber) 组")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.zujianMoonlight)
        case .active:
            Text("第 \(snapshot.setNumber) 组")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.zujianMoonlight)
        case .resting:
            if let endDate = snapshot.restEndDate {
                Text(endDate, style: .timer)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.zujianMistBlue)
            } else {
                Text("休息中")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.zujianMistBlue)
            }
        case .paused:
            Text("训练已暂停")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.zujianMoonlight)
        case .finished:
            Text("\(snapshot.completedSetCount) 组")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.zujianMoonlight)
        }
    }

    private var footnote: String? {
        switch snapshot.phase {
        case .ready: return nil
        case .waiting:
            return snapshot.completedSetCount == 0 ? "等待第一组" : "开始动作即可"
        case .active:
            return snapshot.currentSetStartDate == nil ? nil : "正在识别动作节奏"
        case .resting: return "休息后开始第 \(snapshot.setNumber) 组"
        case .paused: return "点按返回组间"
        case .finished: return "点按查看总结"
        }
    }

    private var restDurationLabel: String {
        let seconds = Int(snapshot.defaultRestDuration.rounded())
        if seconds.isMultiple(of: 60) {
            return "\(seconds / 60) 分钟休息"
        }
        return "\(seconds) 秒休息"
    }
}

private extension Color {
    static let zujianNight = Color.black
    static let zujianMoonlight = Color(red: 0.949, green: 0.957, blue: 0.945)
    static let zujianMistBlue = Color(red: 0.510, green: 0.710, blue: 0.769)
    static let zujianQuietSecondary = Color.zujianMoonlight.opacity(0.60)
}

#Preview(as: .accessoryCircular) {
    ZujianStatusWidget()
} timeline: {
    ZujianWidgetEntry(
        date: Date(),
        snapshot: .ready(defaultRestDuration: 90)
    )
}

#Preview(as: .accessoryRectangular) {
    ZujianStatusWidget()
} timeline: {
    ZujianWidgetEntry(date: Date(), snapshot: .previewResting)
}
