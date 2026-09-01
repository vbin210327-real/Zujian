import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator
#if DEBUG
    @EnvironmentObject private var appRecorder: AppRecordingController
#endif
    @State private var showEndConfirmation = false

    var body: some View {
        VStack(spacing: 8) {
            switch coordinator.state {
            case .waitingForSet:
                WaitingPhaseView()
            case .setActive:
                ActivePhaseView()
            case .resting:
                RestingPhaseView(timer: coordinator.restTimer)
            case .paused:
                PausedPhaseView()
            case .ready, .finished:
                EmptyView()
            }

            if coordinator.state != .paused {
                HStack(spacing: 10) {
                    Button {
                        coordinator.pauseWorkout()
                    } label: {
                        Image(systemName: "pause.fill")
                    }
                    .accessibilityLabel("暂停训练")

                    Button(role: .destructive) {
#if DEBUG
                        appRecorder.recordAction("workout.showEndConfirmation")
#endif
                        showEndConfirmation = true
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .accessibilityLabel("结束训练")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SessionHeader()
            }
        }
        .alert(endAlertTitle, isPresented: $showEndConfirmation) {
            if !coordinator.hasDetectedSet {
                Button("保存并结束") {
                    coordinator.endWorkout(saveLocally: true)
                }
                Button("不保存并结束", role: .destructive) {
                    coordinator.endWorkout(saveLocally: false)
                }
            } else {
                Button("结束训练", role: .destructive) {
                    coordinator.endWorkout(saveLocally: true)
                }
            }
            Button("继续训练", role: .cancel) {}
        } message: {
            Text(endAlertMessage)
        }
        .recordableOverlay(
            .endConfirmation,
            isPresented: showEndConfirmation,
            title: endAlertTitle,
            message: endAlertMessage
        )
        .recordableScreen(.workout)
    }

    private var endAlertTitle: String {
        coordinator.hasDetectedSet ? "结束本次训练？" : "未检测到训练组"
    }

    private var endAlertMessage: String {
        !coordinator.hasDetectedSet
            ? "你可以保存这次记录，也可以直接丢弃。"
            : "训练记录将保存在组间。"
    }
}

private struct SessionHeader: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 1) {
                Text(coordinator.state.title)
                    .fontWeight(.semibold)
                Text(DurationText.concise(coordinator.elapsedTime))
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(Color.quietSecondary)
        }
    }
}

private struct WaitingPhaseView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator

    var body: some View {
        VStack(spacing: 7) {
            Spacer(minLength: 2)
            PetMascotView(
                state: coordinator.completedSetCount == 0 ? .waiting : .next
            )
#if DEBUG
            .frame(height: NativeReplayRuntime.isEnabled ? 62 : 50)
#else
            .frame(height: 62)
#endif
            Text("等待第 \(coordinator.currentSetNumber) 组")
                .font(.headline)
#if DEBUG
            if !NativeReplayRuntime.isEnabled {
                DetectionDiagnosticControls(
                    recorder: coordinator.diagnosticRecorder,
                    beginCapture: coordinator.beginDiagnosticCapture,
                    markMissed: coordinator.markDiagnosticSetMissed
                )
            }
#endif
            Spacer(minLength: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
private struct DetectionDiagnosticControls: View {
    @ObservedObject var recorder: DetectionDiagnosticRecorder
    let beginCapture: () -> Void
    let markMissed: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            Button(recorder.isRecording ? "这组未识别" : "记录下一组") {
                if recorder.isRecording {
                    markMissed()
                } else {
                    beginCapture()
                }
            }
            .buttonStyle(.plain)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.mistBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)

            if let message = recorder.message {
                Text(message)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Color.quietSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
#endif

private struct ActivePhaseView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator

    var body: some View {
        VStack(spacing: 7) {
            ViewThatFits(in: .horizontal) {
                activeStatus(
                    petWidth: 64,
                    petHeight: 50,
                    titleFont: .title2,
                    heartFont: .caption
                )
                activeStatus(
                    petWidth: 52,
                    petHeight: 42,
                    titleFont: .headline,
                    heartFont: .caption2
                )
            }

            Button("手动开始休息") {
                coordinator.manualStartRest()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activeStatus(
        petWidth: CGFloat,
        petHeight: CGFloat,
        titleFont: Font,
        heartFont: Font
    ) -> some View {
        HStack(spacing: 6) {
            PetMascotView(state: .active)
                .frame(width: petWidth, height: petHeight)

            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(coordinator.currentSetNumber) 组")
                    .font(titleFont.weight(.semibold))

                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    if let heartRate = coordinator.currentHeartRate {
                        Text("\(Int(heartRate.rounded()))")
                            .monospacedDigit()
                    } else {
                        Text("—")
                    }
                    Text("BPM")
                        .foregroundStyle(Color.quietSecondary)
                }
                .font(heartFont)
            }
        }
    }
}

private struct RestingPhaseView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator
    @ObservedObject var timer: RestTimerManager

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                restStatus(petWidth: 64, petHeight: 56, timerSize: 44)
                restStatus(petWidth: 48, petHeight: 44, timerSize: 38)
            }
            Text(completedLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.quietSecondary)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("继续训练") {
                    coordinator.continueTraining()
                }
                .buttonStyle(.borderedProminent)

                if coordinator.canReturnToPreviousSet {
                    Button("回到上一组") {
                        coordinator.returnToPreviousSet()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.quietSecondary)
                }
            }
            .font(.caption2)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completedLabel: String {
        coordinator.completedSetCount > 0
            ? "第 \(coordinator.completedSetCount) 组完成"
            : "手动休息"
    }

    private func restStatus(
        petWidth: CGFloat,
        petHeight: CGFloat,
        timerSize: CGFloat
    ) -> some View {
        HStack(spacing: 5) {
            PetMascotView(state: .resting)
                .frame(width: petWidth, height: petHeight)
            Text(DurationText.clock(timer.remaining))
                .font(.system(size: timerSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.mistBlue)
                .fixedSize()
        }
    }
}

private struct PausedPhaseView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator
#if DEBUG
    @EnvironmentObject private var appRecorder: AppRecordingController
#endif
    @State private var showEndConfirmation = false

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            PetMascotView(state: .paused)
                .frame(width: 96, height: 76)
            Spacer(minLength: 0)
            Button("继续") {
                coordinator.resumeWorkout()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("结束训练") {
#if DEBUG
                appRecorder.recordAction("workout.showEndConfirmation")
#endif
                showEndConfirmation = true
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(Color.quietSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("结束本次训练？", isPresented: $showEndConfirmation) {
            if !coordinator.hasDetectedSet {
                Button("保存并结束") { coordinator.endWorkout(saveLocally: true) }
                Button("不保存并结束", role: .destructive) {
                    coordinator.endWorkout(saveLocally: false)
                }
            } else {
                Button("结束训练", role: .destructive) {
                    coordinator.endWorkout(saveLocally: true)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .recordableOverlay(
            .endConfirmation,
            isPresented: showEndConfirmation,
            title: "结束本次训练？"
        )
    }
}

enum PetMascotState: Equatable {
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

    var animatedScale: CGSize {
        switch self {
        case .waiting: return CGSize(width: 1.012, height: 1.006)
        case .active: return CGSize(width: 1.022, height: 1.0)
        case .resting: return CGSize(width: 1.01, height: 1.01)
        case .paused: return CGSize(width: 1.0, height: 1.0)
        case .next: return CGSize(width: 1.012, height: 1.0)
        case .finished: return CGSize(width: 1.025, height: 0.99)
        }
    }

    var horizontalTravel: CGFloat {
        switch self {
        case .waiting, .resting: return 0.8
        case .active: return 2.2
        case .paused: return 0
        case .next: return 1.2
        case .finished: return 1.0
        }
    }

    var artworkScale: CGFloat {
        self == .paused ? 1.58 : 1
    }

    var rotation: Double {
        self == .next ? 1.2 : 0
    }
}

struct PetMascotView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animates = false

    let state: PetMascotState

    var body: some View {
        Image(isLuminanceReduced ? "PetAOD" : state.imageName)
            .resizable()
            .scaledToFit()
            .scaleEffect(
                x: baseArtworkScale
                    * (motionDisabled || !animates ? 1 : state.animatedScale.width),
                y: baseArtworkScale
                    * (motionDisabled || !animates ? 1 : state.animatedScale.height)
            )
            .offset(x: motionDisabled || !animates ? 0 : state.horizontalTravel)
            .rotationEffect(
                .degrees(motionDisabled || !animates ? 0 : state.rotation)
            )
            .onAppear(perform: startAnimation)
            .accessibilityHidden(true)
    }

    private var motionDisabled: Bool {
        isLuminanceReduced || reduceMotion
    }

    private var baseArtworkScale: CGFloat {
        isLuminanceReduced ? 1 : state.artworkScale
    }

    private func startAnimation() {
        guard !motionDisabled else { return }
        switch state {
        case .waiting:
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                animates = true
            }
        case .active:
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                animates = true
            }
        case .resting:
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                animates = true
            }
        case .paused:
            break
        case .next:
            withAnimation(.easeInOut(duration: 0.13).repeatCount(4, autoreverses: true)) {
                animates = true
            }
        case .finished:
            withAnimation(.easeOut(duration: 0.8)) {
                animates = true
            }
        }
    }
}
