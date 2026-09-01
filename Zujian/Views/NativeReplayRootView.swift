#if DEBUG
import SwiftUI

private enum NativeReplayRoute: Hashable {
    case settings
    case history
    case historyDetail(UUID?)
}

/// A Debug-only host that presents the existing production Watch views while a
/// recorded state timeline is injected. It deliberately contains no duplicate
/// drawing code and never shows the recorder or detection debug controls.
struct NativeReplayRootView: View {
    @EnvironmentObject private var replay: NativeReplayController
    @EnvironmentObject private var coordinator: WorkoutCoordinator
    @EnvironmentObject private var history: HistoryStore

    @State private var navigationPath: [NativeReplayRoute] = []
    @State private var showsPermissionHelp = false
    @State private var showsEndConfirmation = false

    var body: some View {
        Group {
            if let errorMessage = replay.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorMessage)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .padding(10)
            } else if let snapshot = replay.frame?.snapshot {
                nativeContent(for: snapshot)
            } else {
                ProgressView()
            }
        }
        .background(Color.night.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.22), value: replay.frame?.snapshot.phase)
        .onAppear {
            synchronizePresentation(animated: false)
        }
        .onChange(of: replay.frame?.snapshot.screen) { _, _ in
            synchronizePresentation(animated: true)
        }
        .onChange(of: replay.frame?.snapshot.screenContext) { _, _ in
            synchronizePresentation(animated: false)
        }
        .onChange(of: replay.frame?.snapshot.overlay.kind) { _, _ in
            synchronizeOverlays()
        }
        .sheet(isPresented: $showsPermissionHelp) {
            WorkoutPermissionHelpView()
                .environmentObject(coordinator)
        }
        .alert(item: $coordinator.notice) { notice in
            Alert(
                title: Text("无法继续"),
                message: Text(notice.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .alert(endAlertTitle, isPresented: $showsEndConfirmation) {
            if !coordinator.hasDetectedSet {
                Button("保存并结束") {}
                Button("不保存并结束", role: .destructive) {}
            } else {
                Button("结束训练", role: .destructive) {}
            }
            Button(endAlertCancelTitle, role: .cancel) {}
        } message: {
            if let endAlertMessage {
                Text(endAlertMessage)
            }
        }
    }

    @ViewBuilder
    private func nativeContent(for snapshot: ReplaySnapshot) -> some View {
        switch snapshot.phase {
        case .waitingForSet, .setActive, .resting, .paused:
            NavigationStack {
                WorkoutView()
            }
        case .finished:
            FinishedView()
        case .ready:
            readyNavigation
        }
    }

    private var readyNavigation: some View {
        NavigationStack(path: $navigationPath) {
            ReadyView()
                .navigationDestination(for: NativeReplayRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsView()
                    case .history:
                        HistoryView()
                    case .historyDetail(let id):
                        if let record = record(for: id) {
                            HistoryDetailView(record: record)
                        } else {
                            ContentUnavailableView(
                                "训练记录不存在",
                                systemImage: "exclamationmark.triangle"
                            )
                        }
                    }
                }
        }
    }

    private func synchronizePresentation(animated: Bool) {
        guard let snapshot = replay.frame?.snapshot else { return }
        let path: [NativeReplayRoute]
        switch snapshot.screen {
        case .settings:
            path = [.settings]
        case .history:
            path = [.history]
        case .historyDetail:
            path = [
                .history,
                .historyDetail(snapshot.screenContext.flatMap(UUID.init(uuidString:)))
            ]
        case .ready, .workout, .finished, .healthAccess, .workoutPermissionHelp:
            path = []
        }

        if navigationPath != path {
            if animated {
                withAnimation(.easeInOut(duration: 0.22)) {
                    navigationPath = path
                }
            } else {
                navigationPath = path
            }
        }
        synchronizeOverlays()
    }

    private func synchronizeOverlays() {
        guard let snapshot = replay.frame?.snapshot else { return }
        showsPermissionHelp = snapshot.screen == .workoutPermissionHelp
            || snapshot.overlay.kind == .workoutPermissionHelp
        showsEndConfirmation = snapshot.overlay.kind == .endConfirmation
    }

    private func record(for id: UUID?) -> WorkoutRecord? {
        if let id, let exactRecord = history.records.first(where: { $0.id == id }) {
            return exactRecord
        }
        return history.records.first
    }

    private var endAlertTitle: String {
        recordedEndOverlay?.title
            ?? (coordinator.hasDetectedSet ? "结束本次训练？" : "未检测到训练组")
    }

    private var endAlertMessage: String? {
        if let recordedEndOverlay {
            return recordedEndOverlay.message
        }
        return coordinator.hasDetectedSet
            ? "训练记录将保存在组间。"
            : "你可以保存这次记录，也可以直接丢弃。"
    }

    private var endAlertCancelTitle: String {
        replay.frame?.snapshot.phase == .paused ? "取消" : "继续训练"
    }

    private var recordedEndOverlay: ReplayOverlay? {
        guard let overlay = replay.frame?.snapshot.overlay,
              overlay.kind == .endConfirmation else {
            return nil
        }
        return overlay
    }
}
#endif
