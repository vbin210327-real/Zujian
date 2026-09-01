import Foundation

final class SettingsManager: ObservableObject {
    private enum Keys {
        static let restDuration = "defaultRestDuration"
    }

    @Published var restDuration: TimeInterval {
        didSet {
            let bounded = min(max(restDuration, 15), 600)
            if bounded != restDuration {
                restDuration = bounded
                return
            }
            UserDefaults.standard.set(restDuration, forKey: Keys.restDuration)
            ZujianWidgetStore.updateDefaultRestDuration(restDuration)
        }
    }

    init() {
        let saved = UserDefaults.standard.double(forKey: Keys.restDuration)
        restDuration = saved > 0 ? min(max(saved, 15), 600) : 90
        ZujianWidgetStore.updateDefaultRestDuration(restDuration)
    }

}
