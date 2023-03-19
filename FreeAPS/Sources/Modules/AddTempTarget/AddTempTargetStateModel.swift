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

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            presets = storage.presets()
            maxValue = settingsManager.preferences.autosensMax
            halfBasal = settingsManager.preferences.halfBasalExerciseTarget
        }

        func enact() {
            let diff = Double(halfBasal - 100)
            let multiplier = percentage - (diff * (percentage / 100))
            let ratio = min(Decimal(percentage / 100), maxValue)
            var target = Decimal(diff + multiplier) / ratio

            if (halfBasal + (halfBasal + target - 100)) <= 0 {
                target = (halfBasal - 100 + (halfBasal - 100) * maxValue) / maxValue
            }
            let lowTarget = target
            let highTarget = lowTarget

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
            let diff = Double(halfBasal - 100)
            let multiplier = percentage - (diff * (percentage / 100))
            let ratio = min(Decimal(percentage / 100), maxValue)
            var target = Decimal(diff + multiplier) / ratio

            if (halfBasal + (halfBasal + target - 100)) <= 0 {
                target = (halfBasal - 100 + (halfBasal - 100) * maxValue) / maxValue
            }
            let lowTarget = target
            let highTarget = lowTarget

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
