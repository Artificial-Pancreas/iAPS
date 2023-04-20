import SwiftUI
import Swinject

extension Statistics_ {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settings.settings.units
        }
    }
}
