import SwiftUI

extension View {
    @ViewBuilder
    func recordableScreen(_ screen: ReplayScreen, context: String? = nil) -> some View {
#if DEBUG
        modifier(RecordableScreenModifier(screen: screen, context: context))
#else
        self
#endif
    }

    @ViewBuilder
    func recordableScrollContainer(_ identifier: String) -> some View {
#if DEBUG
        coordinateSpace(name: RecordingScrollSpace.name(identifier))
#else
        self
#endif
    }

    @ViewBuilder
    func recordableScrollContent(_ identifier: String) -> some View {
#if DEBUG
        modifier(RecordableScrollContentModifier(identifier: identifier))
#else
        self
#endif
    }

    @ViewBuilder
    func recordableScrollAnchor(_ identifier: String, value: Double) -> some View {
#if DEBUG
        modifier(RecordableScrollAnchorModifier(identifier: identifier, value: value))
#else
        self
#endif
    }

    @ViewBuilder
    func recordableOverlay(
        _ kind: ReplayOverlayKind,
        isPresented: Bool,
        title: String? = nil,
        message: String? = nil
    ) -> some View {
#if DEBUG
        modifier(
            RecordableOverlayModifier(
                kind: kind,
                isPresented: isPresented,
                title: title,
                message: message
            )
        )
#else
        self
#endif
    }
}

#if DEBUG
private struct RecordableScreenModifier: ViewModifier {
    @EnvironmentObject private var recorder: AppRecordingController
    let screen: ReplayScreen
    let context: String?

    func body(content: Content) -> some View {
        content
            .onAppear { recorder.screenAppeared(screen, context: context) }
            .onDisappear { recorder.screenDisappeared(screen) }
    }
}

private enum RecordingScrollSpace {
    static func name(_ identifier: String) -> String {
        "zujian.recording.scroll.\(identifier)"
    }
}

private struct RecordingScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct RecordableScrollContentModifier: ViewModifier {
    @EnvironmentObject private var recorder: AppRecordingController
    let identifier: String

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RecordingScrollOffsetPreferenceKey.self,
                        value: [
                            identifier: proxy.frame(
                                in: .named(RecordingScrollSpace.name(identifier))
                            ).minY
                        ]
                    )
                }
            }
            .onPreferenceChange(RecordingScrollOffsetPreferenceKey.self) { values in
                guard let value = values[identifier] else { return }
                recorder.recordScrollPosition(identifier: identifier, rawValue: Double(value))
            }
    }
}

private struct RecordableScrollAnchorModifier: ViewModifier {
    @EnvironmentObject private var recorder: AppRecordingController
    let identifier: String
    let value: Double

    func body(content: Content) -> some View {
        content.onAppear {
            recorder.recordScrollPosition(
                identifier: identifier,
                rawValue: value,
                isAbsolute: true
            )
        }
    }
}

private struct RecordableOverlayModifier: ViewModifier {
    @EnvironmentObject private var recorder: AppRecordingController
    let kind: ReplayOverlayKind
    let isPresented: Bool
    let title: String?
    let message: String?

    func body(content: Content) -> some View {
        content
            .onAppear {
                synchronize(isPresented)
            }
            .onChange(of: isPresented) { _, visible in
                synchronize(visible)
            }
            .onDisappear {
                recorder.presentationOverlayChanged(kind, isPresented: false)
            }
    }

    private func synchronize(_ visible: Bool) {
        recorder.presentationOverlayChanged(
            kind,
            isPresented: visible,
            title: title,
            message: message
        )
    }
}

struct AppRecordingControl: View {
    @EnvironmentObject private var recorder: AppRecordingController

    var body: some View {
        Button {
            recorder.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.72))
                Circle()
                    .stroke(.white.opacity(0.32), lineWidth: 1)
                if recorder.isFinalizing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else if recorder.isRecording {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.red)
                        .frame(width: 13, height: 13)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 15, height: 15)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(recorder.isFinalizing)
        .accessibilityLabel(recorder.isRecording ? "停止 App 自录制" : "开始 App 自录制")
    }
}
#endif
