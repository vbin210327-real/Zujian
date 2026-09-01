import WatchKit

final class HapticManager {
    func setEnded() {
        WKInterfaceDevice.current().play(.start)
    }

    func restEnded() {
        WKInterfaceDevice.current().play(.notification)
    }
}

