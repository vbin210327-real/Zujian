import SwiftUI

struct ReplayCanvasView: View {
    let frame: ReplayFrame

    var body: some View {
        ZStack {
            Color.black
            if let previous = frame.previousSnapshot {
                WatchReplayPage(snapshot: previous, animationElapsed: frame.animationElapsed)
                    .opacity(1 - frame.transitionProgress)
            }
            WatchReplayPage(snapshot: frame.snapshot, animationElapsed: frame.animationElapsed)
                .opacity(frame.transitionProgress)
        }
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

private struct WatchReplayPage: View {
    let snapshot: ReplaySnapshot
    let animationElapsed: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                page(size: proxy.size)
                overlay
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func page(size: CGSize) -> some View {
        switch snapshot.screen {
        case .ready:
            ReadyReplayView(snapshot: snapshot, animationElapsed: animationElapsed)
        case .workout:
            WorkoutReplayView(snapshot: snapshot, animationElapsed: animationElapsed)
        case .finished:
            FinishedReplayView(snapshot: snapshot, animationElapsed: animationElapsed)
        case .settings:
            SettingsReplayView(snapshot: snapshot)
        case .history:
            HistoryReplayView(snapshot: snapshot)
        case .historyDetail:
            HistoryDetailReplayView(snapshot: snapshot)
        case .healthAccess:
            HealthAccessReplayView()
        case .workoutPermissionHelp:
            WorkoutPermissionReplayView()
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if snapshot.overlay.kind == .notice {
            ZStack {
                Color.black.opacity(0.58)
                VStack(spacing: 8) {
                    Text(snapshot.overlay.title ?? "无法继续")
                        .font(.system(size: 16, weight: .semibold))
                    Text(snapshot.overlay.message ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(ReplayPalette.secondary)
                        .multilineTextAlignment(.center)
                    ReplayButton(title: "知道了", prominent: true)
                }
                .padding(12)
                .background(ReplayPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                .padding(16)
            }
        }
    }
}

private struct ReplayNavigationPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(ReplayPalette.foreground)
    }
}

private struct ReadyReplayView: View {
    let snapshot: ReplaySnapshot
    let animationElapsed: TimeInterval

    var body: some View {
        ReplayNavigationPage(title: "组间") {
            VStack(spacing: 0) {
                ReplayMascot(state: .waiting, elapsed: animationElapsed)
                    .frame(height: 58)
                    .padding(.top, 4)

                if let issue = snapshot.startIssue {
                    VStack(spacing: 5) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(ReplayPalette.accent)
                        Text(issue.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(issue.message)
                            .font(.system(size: 10))
                            .foregroundStyle(ReplayPalette.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        ReplayButton(title: "重新检查", prominent: true)
                    }
                    .padding(8)
                    .background(ReplayPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)
                } else if snapshot.isStarting {
                    VStack(spacing: 5) {
                        ProgressView()
                            .tint(ReplayPalette.accent)
                        Text(snapshot.startProgressText)
                            .font(.system(size: 10))
                            .foregroundStyle(ReplayPalette.secondary)
                    }
                    .padding(.vertical, 7)
                } else {
                    ReplayButton(title: "开始训练", systemImage: "play.fill", prominent: true)
                        .padding(.top, 8)
                }

                HStack(spacing: 8) {
                    ReplayButton(
                        title: ReplayDurationText.clock(snapshot.defaultRestDuration),
                        systemImage: "timer"
                    )
                    ReplayIconButton(systemImage: "clock.arrow.circlepath")
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 8)
            .offset(y: snapshot.scrollPositions["ready"] ?? 0)
        }
    }
}

private struct WorkoutReplayView: View {
    let snapshot: ReplaySnapshot
    let animationElapsed: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.phase.title)
                        .fontWeight(.semibold)
                    Text(ReplayDurationText.concise(snapshot.elapsedTime))
                        .monospacedDigit()
                }
                .font(.system(size: 11))
                .foregroundStyle(ReplayPalette.secondary)
                Spacer()
            }
            .frame(height: 30)

            phaseContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if snapshot.phase != .paused {
                HStack(spacing: 10) {
                    ReplayIconButton(systemImage: "pause.fill")
                    ReplayIconButton(systemImage: "stop.fill", destructive: true)
                }
                .frame(height: 29)
            }
        }
        .padding(.horizontal, 8)
        .foregroundStyle(ReplayPalette.foreground)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch snapshot.phase {
        case .waitingForSet:
            VStack(spacing: 7) {
                Spacer(minLength: 0)
                ReplayMascot(
                    state: snapshot.completedSetCount == 0 ? .waiting : .next,
                    elapsed: animationElapsed
                )
                .frame(height: 50)
                Text("等待第 \(snapshot.currentSetNumber) 组")
                    .font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
            }
        case .setActive:
            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    ReplayMascot(state: .active, elapsed: animationElapsed)
                        .frame(width: 64, height: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("第 \(snapshot.currentSetNumber) 组")
                            .font(.system(size: 20, weight: .semibold))
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text(snapshot.currentHeartRate.map { "\(Int($0.rounded()))" } ?? "—")
                                .monospacedDigit()
                            Text("BPM")
                                .foregroundStyle(ReplayPalette.secondary)
                        }
                        .font(.system(size: 12))
                    }
                }
                ReplayCompactButton(title: "手动开始休息")
                Spacer(minLength: 0)
            }
        case .resting:
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    ReplayMascot(state: .resting, elapsed: animationElapsed)
                        .frame(width: 64, height: 56)
                    Text(ReplayDurationText.clock(snapshot.restRemaining))
                        .font(.system(size: 44, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ReplayPalette.accent)
                        .fixedSize()
                }
                Text(
                    snapshot.completedSetCount > 0
                        ? "第 \(snapshot.completedSetCount) 组完成"
                        : "手动休息"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ReplayPalette.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    ReplayCompactButton(title: "继续训练", prominent: true)
                    if snapshot.canReturnToPreviousSet {
                        Text("回到上一组")
                            .font(.system(size: 10))
                            .foregroundStyle(ReplayPalette.secondary)
                    }
                }
            }
        case .paused:
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                ReplayMascot(state: .paused, elapsed: animationElapsed)
                    .frame(width: 96, height: 76)
                Spacer(minLength: 0)
                ReplayCompactButton(title: "继续", prominent: true)
                Text("结束训练")
                    .font(.system(size: 11))
                    .foregroundStyle(ReplayPalette.secondary)
            }
        case .ready, .finished:
            EmptyView()
        }
    }
}

private struct FinishedReplayView: View {
    let snapshot: ReplaySnapshot
    let animationElapsed: TimeInterval

    var body: some View {
        VStack(spacing: 10) {
            ReplayMascot(state: .finished, elapsed: animationElapsed)
                .frame(height: 68)
            Text("训练完成")
                .font(.system(size: 17, weight: .semibold))
            if let summary = snapshot.summary {
                HStack(spacing: 16) {
                    ReplayMetric(value: ReplayDurationText.concise(summary.duration), label: "时长")
                    ReplayMetric(value: "\(summary.sets.count)", label: "组数")
                }
                if !summary.sets.isEmpty {
                    Divider().overlay(ReplayPalette.secondary.opacity(0.4))
                    ForEach(summary.sets) { set in
                        ReplaySetRow(set: set)
                    }
                }
            }
            ReplayCompactButton(title: "完成", prominent: true)
        }
        .padding(.horizontal, 8)
        .offset(y: snapshot.scrollPositions["finished"] ?? 0)
        .foregroundStyle(ReplayPalette.foreground)
    }
}

private struct SettingsReplayView: View {
    let snapshot: ReplaySnapshot

    var body: some View {
        ReplayNavigationPage(title: "休息时间") {
            VStack(spacing: 8) {
                HStack {
                    Text("默认休息")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ReplayPalette.secondary)
                    Spacer()
                }
                HStack {
                    Text("时长")
                        .font(.system(size: 13))
                    Spacer()
                    Text(ReplayDurationText.clock(snapshot.defaultRestDuration))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ReplayPalette.accent)
                }
                .padding(10)
                .background(ReplayPalette.surface, in: RoundedRectangle(cornerRadius: 11))

                HStack(spacing: 6) {
                    ForEach([60, 90, 120], id: \.self) { seconds in
                        Text("\(seconds)")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                snapshot.defaultRestDuration == Double(seconds)
                                    ? ReplayPalette.accent.opacity(0.35)
                                    : ReplayPalette.surface,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                    }
                }
                Spacer()
            }
            .padding(8)
        }
    }
}

private struct HistoryReplayView: View {
    let snapshot: ReplaySnapshot

    var body: some View {
        ReplayNavigationPage(title: "训练记录") {
            if snapshot.history.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(ReplayPalette.secondary)
                    Text("暂无训练")
                        .font(.system(size: 15, weight: .semibold))
                    Text("完成训练后，记录会保存在这里。")
                        .font(.system(size: 10))
                        .foregroundStyle(ReplayPalette.secondary)
                }
            } else {
                VStack(spacing: 5) {
                    ForEach(snapshot.history.prefix(6)) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ReplayDateText.monthDayTime(record.startDate))
                                    .font(.system(size: 11, weight: .semibold))
                                Text("\(record.sets.count) 组 · \(ReplayDurationText.concise(record.duration))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(ReplayPalette.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ReplayPalette.secondary)
                        }
                        .padding(8)
                        .background(ReplayPalette.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(8)
                .offset(y: -(snapshot.scrollPositions["history"] ?? 0) * 51)
            }
        }
    }
}

private struct HistoryDetailReplayView: View {
    let snapshot: ReplaySnapshot

    private var record: ReplayWorkoutSummary? {
        if let context = snapshot.screenContext,
           let id = UUID(uuidString: context),
           let selected = snapshot.history.first(where: { $0.id == id }) {
            return selected
        }
        return snapshot.history.first
    }

    var body: some View {
        ReplayNavigationPage(title: record.map { ReplayDateText.monthDay($0.startDate) } ?? "训练") {
            if let record {
                VStack(spacing: 5) {
                    HStack {
                        Text("时长")
                        Spacer()
                        Text(ReplayDurationText.concise(record.duration))
                    }
                    HStack {
                        Text("组数")
                        Spacer()
                        Text("\(record.sets.count)")
                    }
                    .padding(.bottom, 4)
                    ForEach(record.sets.prefix(5)) { set in
                        ReplaySetRow(set: set)
                    }
                    Spacer()
                }
                .font(.system(size: 11))
                .padding(8)
            }
        }
    }
}

private struct HealthAccessReplayView: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 34))
                .foregroundStyle(ReplayPalette.accent)
            Text("开始前，确认健康权限")
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
            ReplayPermissionRow(
                icon: "figure.strengthtraining.traditional",
                title: "体能训练（必须打开）",
                detail: "用于息屏和后台稳定运行"
            )
            ReplayPermissionRow(
                icon: "heart.fill",
                title: "心率（可选）",
                detail: "用于每组平均与最高心率"
            )
            Text("组间不会把整场训练保存到健康。")
                .font(.system(size: 9))
                .foregroundStyle(ReplayPalette.secondary)
            ReplayButton(title: "继续", prominent: true)
        }
        .padding(10)
        .foregroundStyle(ReplayPalette.foreground)
    }
}

private struct WorkoutPermissionReplayView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 30))
                .foregroundStyle(ReplayPalette.accent)
            Text("打开“体能训练”")
                .font(.system(size: 16, weight: .semibold))
            Text("在配对的 iPhone 上：")
                .font(.system(size: 10))
                .foregroundStyle(ReplayPalette.secondary)
            ForEach(Array(["打开“健康”App", "摘要 → 右上角头像", "App → 组间", "打开“体能训练”"].enumerated()), id: \.offset) { index, title in
                HStack(spacing: 7) {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 18, height: 18)
                        .background(ReplayPalette.accent, in: Circle())
                    Text(title).font(.system(size: 10))
                    Spacer()
                }
            }
            ReplayButton(title: "已经打开", prominent: true)
        }
        .padding(9)
        .foregroundStyle(ReplayPalette.foreground)
    }
}

private struct ReplayPermissionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(ReplayPalette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .semibold))
                Text(detail).font(.system(size: 9)).foregroundStyle(ReplayPalette.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ReplayMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(ReplayPalette.secondary)
        }
    }
}

private struct ReplaySetRow: View {
    let set: ReplaySetSummary

    var body: some View {
        HStack {
            Text("第 \(set.number) 组")
                .font(.system(size: 10, weight: .semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("平均 \(heartRate(set.averageHeartRate))")
                Text("最高 \(heartRate(set.maximumHeartRate))")
                    .foregroundStyle(ReplayPalette.secondary)
            }
            .font(.system(size: 9))
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func heartRate(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "—"
    }
}

private struct ReplayButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(prominent ? Color.black : ReplayPalette.foreground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            prominent ? ReplayPalette.accent : ReplayPalette.surface,
            in: Capsule()
        )
    }
}

/// Renderer-only approximation of watchOS `.bordered` / `.controlSize(.small)`.
/// Unlike `ReplayButton`, this keeps the intrinsic label width, matching the
/// compact controls used by the real WorkoutView.
private struct ReplayCompactButton: View {
    let title: String
    var prominent = false

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.black : ReplayPalette.foreground)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(
                prominent ? ReplayPalette.accent : ReplayPalette.surface,
                in: Capsule()
            )
    }
}

private struct ReplayIconButton: View {
    let systemImage: String
    var destructive = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(destructive ? Color.red : ReplayPalette.foreground)
            .frame(width: 39, height: 27)
            .background(ReplayPalette.surface, in: Capsule())
    }
}

private enum ReplayMascotState {
    case waiting
    case active
    case resting
    case paused
    case next
    case finished

    var imageName: String {
        switch self {
        case .waiting: return "PetWaiting"
        case .active: return "PetActive"
        case .resting: return "PetResting"
        case .paused: return "PetPaused"
        case .next: return "PetNext"
        case .finished: return "PetFinished"
        }
    }

    var targetScale: CGSize {
        switch self {
        case .waiting: return CGSize(width: 1.012, height: 1.006)
        case .active: return CGSize(width: 1.022, height: 1)
        case .resting: return CGSize(width: 1.01, height: 1.01)
        case .paused: return CGSize(width: 1, height: 1)
        case .next: return CGSize(width: 1.012, height: 1)
        case .finished: return CGSize(width: 1.025, height: 0.99)
        }
    }

    var travel: Double {
        switch self {
        case .waiting, .resting: return 0.8
        case .active: return 2.2
        case .paused: return 0
        case .next: return 1.2
        case .finished: return 1
        }
    }

    var rotation: Double { self == .next ? 1.2 : 0 }
    var artworkScale: Double { self == .paused ? 1.58 : 1 }
}

private struct ReplayMascot: View {
    let state: ReplayMascotState
    let elapsed: TimeInterval

    var body: some View {
        let progress = animationProgress
        Image(state.imageName)
            .resizable()
            .scaledToFit()
            .scaleEffect(
                x: state.artworkScale * interpolated(1, state.targetScale.width, progress),
                y: state.artworkScale * interpolated(1, state.targetScale.height, progress)
            )
            .offset(x: state.travel * progress)
            .rotationEffect(.degrees(state.rotation * progress))
    }

    private var animationProgress: Double {
        switch state {
        case .waiting:
            return repeatingEase(legDuration: 1.9)
        case .active:
            return repeatingEase(legDuration: 0.55)
        case .resting:
            return repeatingEase(legDuration: 2.2)
        case .paused:
            return 0
        case .next:
            guard elapsed < 1.04 else { return 0 }
            return repeatingEase(legDuration: 0.13)
        case .finished:
            return ReplayEasing.easeOut(min(1, elapsed / 0.8))
        }
    }

    private func repeatingEase(legDuration: TimeInterval) -> Double {
        guard legDuration > 0 else { return 0 }
        let cyclePosition = elapsed.truncatingRemainder(dividingBy: legDuration * 2) / legDuration
        let linear = cyclePosition <= 1 ? cyclePosition : 2 - cyclePosition
        return ReplayEasing.easeInOut(linear)
    }

    private func interpolated(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start + (end - start) * progress
    }
}

private enum ReplayPalette {
    static let foreground = Color(red: 0.949, green: 0.957, blue: 0.945)
    static let accent = Color(red: 0.510, green: 0.710, blue: 0.769)
    static let secondary = foreground.opacity(0.58)
    static let surface = foreground.opacity(0.08)
}

private enum ReplayDurationText {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func concise(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private enum ReplayDateText {
    static func monthDayTime(_ date: Date) -> String {
        formatter("M月d日 HH:mm").string(from: date)
    }

    static func monthDay(_ date: Date) -> String {
        formatter("M月d日").string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }
}
