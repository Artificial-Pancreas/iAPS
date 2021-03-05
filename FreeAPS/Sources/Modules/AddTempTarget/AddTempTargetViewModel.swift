import SwiftUI

extension AddTempTarget {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AddTempTargetProvider {
        @Injected() private var storage: TempTargetsStorage!
        @Injected() private var settingsManager: SettingsManager!

        @Published var low: Decimal = 0
        @Published var high: Decimal = 0
        @Published var duration: Decimal = 0
        @Published var date = Date()

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
        }

        func add() {
            var lowTarget = low
            var highTarget = high

            if units == .mmolL {
                lowTarget = Decimal(Int(lowTarget / GlucoseUnits.exchangeRate))
                highTarget = Decimal(Int(highTarget / GlucoseUnits.exchangeRate))
            }

            highTarget = max(highTarget, lowTarget)
            let entry = TempTarget(
                createdAt: date,
                targetTop: highTarget,
                targetBottom: lowTarget,
                duration: duration,
                enteredBy: TempTarget.manual
            )
            storage.storeTempTargets([entry])

            showModal(for: nil)
        }
    }
}
