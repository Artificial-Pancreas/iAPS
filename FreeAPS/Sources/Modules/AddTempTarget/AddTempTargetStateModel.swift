import CoreData
import SwiftUI

extension AddTempTarget {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var storage: TempTargetsStorage!
        @Injected() var apsManager: APSManager!

        @Published var low: Decimal = 0
        @Published var high: Decimal = 0
        @Published var duration: Decimal = 0
        @Published var date = Date()
        @Published var newPresetName = ""
        @Published var presets: [TempTarget] = []
        @Published var percentage = 100.0
        @Published var maxValue: Decimal = 1.2
        @Published var halfBasal: Decimal = 160
        @Published var viewPercantage = false

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            presets = storage.presets()
            maxValue = settingsManager.preferences.autosensMax
            halfBasal = settingsManager.preferences.halfBasalExerciseTarget
        }

        func enact() {
            var lowTarget = low

            if viewPercantage {
                var ratio = Decimal(percentage / 100)
                let hB = halfBasal
                let c = hB - 100
                var target = (c / ratio) - c + 100

                if c * (c + target - 100) <= 0 {
                    ratio = maxValue
                    target = (c / ratio) - c + 100
                }
                lowTarget = target
                lowTarget = Decimal(round(Double(target)))
            }
            var highTarget = lowTarget

            if units == .mmolL, !viewPercantage {
                lowTarget = lowTarget.asMgdL
                highTarget = highTarget.asMgdL
            }

            let entry = TempTarget(
                name: TempTarget.custom,
                createdAt: date,
                targetTop: highTarget,
                targetBottom: lowTarget,
                duration: duration,
                enteredBy: TempTarget.manual,
                reason: TempTarget.custom
            )
            storage.storeTempTargets([entry])
            showModal(for: nil)
        }

        func cancel() {
            storage.storeTempTargets([TempTarget.cancel(at: Date())])
            showModal(for: nil)
        }

        func save() {
            var lowTarget = low

            if viewPercantage {
                var ratio = Decimal(percentage / 100)
                let hB = halfBasal
                let c = hB - 100
                var target = (c / ratio) - c + 100

                if c * (c + target - 100) <= 0 {
                    ratio = maxValue
                    target = (c / ratio) - c + 100
                }
                lowTarget = target
                lowTarget = Decimal(round(Double(target)))
            }
            var highTarget = lowTarget

            if units == .mmolL, !viewPercantage {
                lowTarget = lowTarget.asMgdL
                highTarget = highTarget.asMgdL
            }

            let entry = TempTarget(
                name: newPresetName.isEmpty ? TempTarget.custom : newPresetName,
                createdAt: Date(),
                targetTop: highTarget,
                targetBottom: lowTarget,
                duration: duration,
                enteredBy: TempTarget.manual,
                reason: newPresetName.isEmpty ? TempTarget.custom : newPresetName
            )
            presets.append(entry)
            storage.storePresets(presets)
        }

        func enactPreset(id: String) {
            if var preset = presets.first(where: { $0.id == id }) {
                preset.createdAt = Date()
                storage.storeTempTargets([preset])
                showModal(for: nil)
            }
        }

        func removePreset(id: String) {
            presets = presets.filter { $0.id != id }
            storage.storePresets(presets)
        }
    }
}
