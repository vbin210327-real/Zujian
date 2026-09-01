import SwiftUI

struct ReadyView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator
    @EnvironmentObject private var settings: SettingsManager

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PetMascotView(state: .waiting)
                    .frame(height: 58)
                    .padding(.top, 4)

                if let issue = coordinator.startIssue {
                    VStack(spacing: 6) {
                        Text(issue.title)
                            .font(.caption.weight(.semibold))
                        Text(issue.message)
                            .font(.caption2)
                            .foregroundStyle(Color.quietSecondary)
                            .multilineTextAlignment(.center)

                        Button {
                            coordinator.retryStartingWorkout()
                        } label: {
                            if coordinator.isStarting {
                                HStack(spacing: 5) {
                                    ProgressView()
                                    Text("正在检查…")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("重新检查")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(coordinator.isStarting)

                        Button("稍后") {
                            coordinator.dismissStartIssue()
                        }
                        .font(.caption2)
                    }
                    .padding(8)
                    .background(Color.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 12)
                }

                if coordinator.startIssue == nil {
                    Group {
                        if coordinator.isStarting {
                            VStack(spacing: 5) {
                                ProgressView()
                                Text(coordinator.startProgressText)
                                    .font(.caption2)
                                    .foregroundStyle(Color.quietSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .accessibilityElement(children: .combine)
                        } else {
                            Button {
                                coordinator.startWorkout()
                            } label: {
                                Label("开始训练", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 8)
                }

                HStack(spacing: 8) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label(DurationText.clock(settings.restDuration), systemImage: "timer")
                    }

                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("训练记录")
                }
                .font(.caption)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 8)
            .recordableScrollContent("ready")
        }
        .recordableScrollContainer("ready")
        .navigationTitle("组间")
        .toolbarTitleDisplayMode(.large)
        .sheet(
            isPresented: $coordinator.showsHealthAccessIntroduction,
            onDismiss: coordinator.healthAccessIntroductionDidDismiss
        ) {
            HealthAccessIntroductionView()
                .environmentObject(coordinator)
        }
        .recordableScreen(.ready)
    }
}

struct WorkoutPermissionHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                permissionStep(1, "按下数码表冠，打开“设置”")
                permissionStep(2, "找到“健康”")
                permissionStep(3, "找到“App”")
                permissionStep(4, "选择“组间”，打开“体能训练”")

                Button("知道了") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 9)
        }
        .recordableScreen(.workoutPermissionHelp)
    }

    private func permissionStep(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 7) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.night)
                .frame(width: 18, height: 18)
                .background(Color.mistBlue, in: Circle())
            Text(title)
                .font(.caption2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }
}

private struct HealthAccessIntroductionView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator
    @State private var showsPermissionReason = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    Image("PetPermission")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .frame(height: 76)
                        .clipped()
                        .accessibilityHidden(true)

                    Text("组间需要你的健康权限")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 14) {
                        permissionItem(
                            icon: "figure.strengthtraining.traditional",
                            title: "体能训练"
                        )
                        permissionItem(
                            icon: "heart.fill",
                            title: "心率"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showsPermissionReason.toggle()
                        }
                    } label: {
                        HStack {
                            Text("为什么需要？")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.moonlight.opacity(0.78))
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.moonlight.opacity(0.78))
                                .rotationEffect(.degrees(showsPermissionReason ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showsPermissionReason ? "已展开" : "已收起")

                    if showsPermissionReason {
                        Text("“体能训练”用于启动系统训练，让计时和动作识别在息屏后仍能继续。“心率”是可选的，用于计算每组的平均和最高心率。")
                            .font(.caption2)
                            .foregroundStyle(Color.quietSecondary)
                            .multilineTextAlignment(.leading)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if coordinator.healthAccessIntroductionMode == .changeInSettings {
                        NavigationLink {
                            WorkoutPermissionHelpView()
                        } label: {
                            Text("如何开启")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if let message = coordinator.healthAccessStatusMessage {
                            Text(message)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.mistBlue)
                                .multilineTextAlignment(.center)
                        }

                        Button("我已打开，重新检查") {
                            coordinator.continueAfterHealthAccessIntroduction()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("去授权") {
                            coordinator.continueAfterHealthAccessIntroduction()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("暂不开始") {
                        coordinator.cancelHealthAccessIntroduction()
                    }
                    .font(.caption2)
                }
                .padding(.horizontal, 10)
            }
            .recordableScreen(.healthAccess)
        }
    }

    private func permissionItem(icon: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(Color.mistBlue)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }

}
