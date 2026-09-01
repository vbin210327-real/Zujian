import Foundation

final class RestTimerManager: ObservableObject {
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning = false

    var onFinished: (() -> Void)?
    var expectedStartDate: Date? { startDate }
    var expectedEndDate: Date? { endDate }

    private var startDate: Date?
    private var endDate: Date?
    private var timer: Timer?
    private var pausedRemaining: TimeInterval?

    func start(duration: TimeInterval) {
        stop(clearRemaining: false)
        remaining = max(0, duration)
        let now = Date()
        startDate = now
        endDate = now.addingTimeInterval(remaining)
        pausedRemaining = nil
        isRunning = true
        scheduleTimer()
        tick()
    }

    func pause() {
        guard isRunning else { return }
        tick()
        pausedRemaining = remaining
        isRunning = false
        startDate = nil
        endDate = nil
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard let pausedRemaining, pausedRemaining > 0 else { return }
        remaining = pausedRemaining
        self.pausedRemaining = nil
        let now = Date()
        startDate = now
        endDate = now.addingTimeInterval(remaining)
        isRunning = true
        scheduleTimer()
    }

    func cancel() {
        stop(clearRemaining: true)
    }

    func stop(clearRemaining: Bool = true) {
        timer?.invalidate()
        timer = nil
        startDate = nil
        endDate = nil
        pausedRemaining = nil
        isRunning = false
        if clearRemaining {
            remaining = 0
        }
    }

#if DEBUG
    func applyNativeReplay(remaining: TimeInterval, isRunning: Bool) {
        timer?.invalidate()
        timer = nil
        startDate = nil
        endDate = nil
        pausedRemaining = nil

        let boundedRemaining = max(0, remaining)
        if self.remaining != boundedRemaining {
            self.remaining = boundedRemaining
        }
        if self.isRunning != isRunning {
            self.isRunning = isRunning
        }
    }
#endif

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        guard remaining <= 0 else { return }
        stop(clearRemaining: true)
        onFinished?()
    }
}
