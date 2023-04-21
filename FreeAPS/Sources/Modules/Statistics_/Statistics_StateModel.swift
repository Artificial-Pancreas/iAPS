import SwiftUI
import Swinject

extension Statistics_ {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!

        @Published var overrideHbA1cUnit: Bool = false

        override func subscribe() {
            subscribeSetting(\.overrideHbA1cUnit, on: $overrideHbA1cUnit) { overrideHbA1cUnit = $0 }
        }
    }
}
