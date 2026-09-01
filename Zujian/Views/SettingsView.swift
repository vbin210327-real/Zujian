import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
#if DEBUG
    @EnvironmentObject private var appRecorder: AppRecordingController
#endif

    var body: some View {
        List {
            Section("默认休息") {
                Picker("时长", selection: $settings.restDuration) {
                    ForEach(Array(stride(from: 15, through: 600, by: 15)), id: \.self) { seconds in
                        Text(DurationText.clock(TimeInterval(seconds)))
                            .tag(TimeInterval(seconds))
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 88)

                HStack(spacing: 6) {
                    ForEach([60, 90, 120], id: \.self) { seconds in
                        Button {
                            settings.restDuration = TimeInterval(seconds)
                        } label: {
                            Text("\(seconds)")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(
                            settings.restDuration == TimeInterval(seconds)
                                ? Color.mistBlue
                                : Color.quietSecondary
                        )
                        .accessibilityLabel("\(seconds) 秒")
                    }
                }
                .listRowBackground(Color.clear)
            }
#if DEBUG
            if !NativeReplayRuntime.isEnabled {
                Section("App 自录制") {
                    Toggle("显示录制按钮", isOn: $appRecorder.showsControl)
                        .disabled(appRecorder.isRecording)

                    Text("红色按钮只记录组间 App 的状态；导出视频不会包含这个按钮。")
                        .font(.caption2)
                        .foregroundStyle(Color.quietSecondary)

                    if appRecorder.lastRecordingURL != nil {
                        Button("重新发送上次录制") {
                            appRecorder.retryLastTransfer()
                        }
                    }

                    Text(appRecorder.statusText)
                        .font(.caption2)
                        .foregroundStyle(Color.quietSecondary)
                }
            }
#endif
        }
        .navigationTitle("休息时间")
        .recordableScreen(.settings)
    }
}
