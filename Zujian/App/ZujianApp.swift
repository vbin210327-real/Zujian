import SwiftUI

@main
struct ZujianApp: App {
    @StateObject private var settings: SettingsManager
    @StateObject private var history: HistoryStore
    @StateObject private var coordinator: WorkoutCoordinator
#if DEBUG
    @StateObject private var appRecorder: AppRecordingController
    @StateObject private var nativeReplay: NativeReplayController
#endif

    init() {
        let settings = SettingsManager()
        let history = HistoryStore()
        let coordinator = WorkoutCoordinator(settings: settings, history: history)
#if DEBUG
        let appRecorder = AppRecordingController()
        if !NativeReplayRuntime.isEnabled {
            coordinator.appRecordingController = appRecorder
            appRecorder.bind(coordinator: coordinator, settings: settings, history: history)
        }
        let nativeReplay = NativeReplayController(
            coordinator: coordinator,
            settings: settings,
            history: history
        )
        _appRecorder = StateObject(wrappedValue: appRecorder)
        _nativeReplay = StateObject(wrappedValue: nativeReplay)
#endif
        _settings = StateObject(wrappedValue: settings)
        _history = StateObject(wrappedValue: history)
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if nativeReplay.isEnabled {
                    NativeReplayRootView()
                } else {
                    RootView()
                }
#else
                RootView()
#endif
            }
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(coordinator)
#if DEBUG
                .environmentObject(appRecorder)
                .environmentObject(nativeReplay)
#endif
                .tint(.mistBlue)
                .foregroundStyle(Color.moonlight)
                .preferredColorScheme(.dark)
        }
    }
}

extension Color {
    static let night = Color.black
    static let moonlight = Color(red: 0.949, green: 0.957, blue: 0.945)
    static let mistBlue = Color(red: 0.510, green: 0.710, blue: 0.769)
    static let quietSecondary = Color.moonlight.opacity(0.58)
    static let quietSurface = Color.moonlight.opacity(0.06)
}
