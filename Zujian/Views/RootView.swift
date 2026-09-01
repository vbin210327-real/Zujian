import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator
#if DEBUG
    @EnvironmentObject private var appRecorder: AppRecordingController
#endif

    var body: some View {
        Group {
            switch coordinator.state {
            case .ready:
                NavigationStack {
                    ReadyView()
                }
            case .finished:
                FinishedView()
            case .waitingForSet, .setActive, .resting, .paused:
                NavigationStack {
                    WorkoutView()
                }
            }
        }
        .background(Color.night.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.22), value: coordinator.state)
        .alert(item: $coordinator.notice) { notice in
            Alert(
                title: Text("无法继续"),
                message: Text(notice.message),
                dismissButton: .default(Text("知道了"))
            )
        }
#if DEBUG
        .overlay(alignment: .topTrailing) {
            if appRecorder.showsControl {
                AppRecordingControl()
                    .padding(.trailing, 7)
                    .padding(.top, 7)
                    .zIndex(10)
            }
        }
#endif
    }
}
