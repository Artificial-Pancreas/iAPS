import SwiftDate
import SwiftUI

extension Calibrations {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var calibrationService: CalibrationService!
        @Injected() var settingsManager: SettingsManager!

        @Published var slope: Double = 1
        @Published var intercept: Double = 1
        @Published var calibration: Decimal = 0

        @Published var calibrationsCount = 0

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            slope = calibrationService.slope
            intercept = calibrationService.intercept

            units = settingsManager.settings.units
            calibrationsCount = calibrationService.calibrations.count
        }

        func addCalibration() {
            defer {
                hideModal()
            }

            var glucose = calibration
            if units == .mmolL {
                glucose = calibration.asMgdL
            }

            guard let lastGlucose = glucoseStorage.recent().last,
                  lastGlucose.dateString.addingTimeInterval(60 * 4.5) > Date(),
                  let unfiltered = lastGlucose.unfiltered
            else {
                warning(.service, "Glucose is invalid for calibration")
                return
            }

            let calibration = Calibration(x: Double(unfiltered), y: Double(glucose))

            calibrationService.addCalibration(calibration)
        }

        func removeLast() {
            calibrationService.removeLast()
            hideModal()
        }

        func removeAll() {
            calibrationService.removeAllCalibrations()
            hideModal()
        }
    }
}
