import SwiftUI
import Swinject

extension Calibrations {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var calibrationService: CalibrationService!

        @Published var newCalibration: Decimal = 0
        @Published var calibrations: [Calibration] = []
        @Published var items: [Item] = []
        @Published var units: GlucoseUnits = .mmolL

        @Setting(\.calibrationRobustFit) var robustFit = false
        @Setting(\.calibrationRelaxLimits) var relaxLimits = false

        /// when off, the calibration is paired with the newest reading
        @Published var useCustomDate: Bool = false
        @Published var calibrationDate = Date()
        @Published var error: LookupError?

        @Published var isUpdatingHistory: Bool = false
        @Published var historyMessage: String?

        override func subscribe() async {
            let settings = await settingsManager.settings
            units = settings.units
            setupCalibrations()
        }

        private func setupCalibrations() {
            calibrations = calibrationService.calibrations
            items = calibrations.map {
                Item(calibration: $0)
            }
        }

        var fit: CalibrationFit {
            CalibrationFitting.fit(
                calibrations,
                options: CalibrationOptions(robustFit: robustFit, relaxLimits: relaxLimits)
            )
        }

        var slope: Double {
            fit.slope
        }

        var intercept: Double {
            fit.intercept
        }

        func calibrate(_ value: Double) -> Double {
            fit.calibrate(value)
        }

        var canUseRobustFit: Bool {
            calibrations.count >= CalibrationFitting.minimumRobustCount
        }

        var showRelaxLimits: Bool {
            fit.isLimited || relaxLimits
        }

        var limitExplanation: String? {
            let fit = self.fit
            var parts: [String] = []

            if fit.slopeIsLimited {
                parts.append(String(
                    format: NSLocalizedString("the slope of %@ was limited to %@", comment: "Calibration limit"),
                    Self.decimals(fit.fittedSlope), Self.decimals(fit.slope)
                ))
            }
            if fit.interceptIsLimited {
                parts.append(String(
                    format: NSLocalizedString("the offset of %@ was limited to %@", comment: "Calibration limit"),
                    displayed(fit.fittedIntercept), displayed(fit.intercept)
                ))
            }

            guard parts.isNotEmpty else { return nil }

            return String(
                format: NSLocalizedString(
                    "The calibrations ask for more correction than is allowed: %@.",
                    comment: "Calibration limit"
                ),
                parts.joined(separator: ", ")
            )
        }

        var spreadExplanation: String? {
            let fit = self.fit
            guard fit.count >= 2, !fit.estimatedSlope else { return nil }

            return String(
                format: NSLocalizedString(
                    "The calibrations only span %@ %@ of sensor value, too little to tell the slope from noise, so an offset alone is applied. Add one at a clearly different glucose level.",
                    comment: "Calibration spread"
                ),
                displayed(fit.spread), units.rawValue
            )
        }

        private func displayed(_ mgdl: Double) -> String {
            let value = units == .mmolL ? mgdl.asMmolL : Decimal(mgdl)
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = units == .mmolL ? 1 : 0
            return formatter.string(from: value as NSNumber) ?? "--"
        }

        private static func decimals(_ value: Double) -> String {
            String(format: "%.2f", value)
        }

        var effectiveDate: Date {
            useCustomDate ? calibrationDate : Date()
        }

        var pairedReading: Result<PairedReading, LookupError> {
            let readings = appCoordinator.glucoseRaw.value
            let date = effectiveDate

            return RawGlucoseLookup.value(at: date, in: readings).map {
                PairedReading(uncalibrated: $0, rate: RawGlucoseLookup.rate(around: date, in: readings))
            }
        }

        var dateRange: ClosedRange<Date> {
            let now = Date()
            let oldest = appCoordinator.glucoseRaw.value
                .last { $0.type == GlucoseType.sgv.rawValue }?
                .dateString

            guard let oldest, oldest < now else { return now ... now }

            return oldest ... now
        }

        func addCalibration() {
            defer {
                UIApplication.shared.endEditing()
                setupCalibrations()
            }

            var glucose = newCalibration
            if units == .mmolL {
                glucose = newCalibration.asMgdL
            }

            let date = effectiveDate

            switch RawGlucoseLookup.value(at: date, in: appCoordinator.glucoseRaw.value) {
            case let .success(uncalibrated):
                error = nil
                calibrationService.addCalibration(Calibration(x: uncalibrated, y: Double(glucose), date: date))
                newCalibration = 0
            case let .failure(lookupError):
                error = lookupError
                info(.service, "Cannot calibrate: \(lookupError.message)")
            }
        }

        func recalibrateHistory() {
            updateHistory(clearingCalibrations: false)
        }

        func removeAllAndResetHistory() {
            updateHistory(clearingCalibrations: true)
        }

        private func updateHistory(clearingCalibrations: Bool) {
            guard !isUpdatingHistory else { return }

            isUpdatingHistory = true
            historyMessage = nil

            let snapshot = clearingCalibrations ? CalibrationFit() : fit
            let transform: @Sendable(Double) -> Double = { snapshot.calibrate($0) }

            let service = calibrationService!
            let removeCalibrations: @Sendable() async -> Void = { service.removeAllCalibrations() }
            let beforeRewrite = clearingCalibrations ? removeCalibrations : nil

            Task {
                let outcome = await glucoseStorage.recalibrateCurrentSession(
                    with: transform,
                    beforeRewrite: beforeRewrite
                )

                switch outcome {
                case .noSensorSession:
                    historyMessage = NSLocalizedString(
                        "No readings from this sensor session found.",
                        comment: "Calibration history result"
                    )

                case let .updated(count):
                    if clearingCalibrations {
                        setupCalibrations() // the service was already cleared, refresh the screen
                    }
                    historyMessage = count > 0
                        ? String(
                            format: NSLocalizedString(
                                "%d stored readings updated.",
                                comment: "Calibration history result"
                            ),
                            count
                        )
                        : NSLocalizedString(
                            "No stored readings needed updating.",
                            comment: "Calibration history result"
                        )
                }

                isUpdatingHistory = false
            }
        }

        func removeLast() {
            calibrationService.removeLast()
            setupCalibrations()
        }

        func removeAll() {
            calibrationService.removeAllCalibrations()
            setupCalibrations()
        }

        func removeAtIndex(_ index: Int) {
            let calibration = calibrations[index]
            calibrationService.removeCalibration(calibration)
            setupCalibrations()
        }
    }
}
