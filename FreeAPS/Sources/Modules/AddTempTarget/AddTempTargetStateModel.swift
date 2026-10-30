import SwiftUI

extension AddTempTarget {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var storage: TempTargetsStorage!
        @Injected() var apsManager: APSManager!

        @Published var low: Decimal = 0
        // @Published var target: Decimal = 0
        @Published var high: Decimal = 0
        @Published var duration: Decimal = 0
        @Published var date = Date()
        @Published var newPresetName = ""
        @Published var presets: [TempTarget] = []
        @Published var percentage = 100.0
        @Published var maxValue: Decimal = 1.2
        @Published var viewPercantage = false
        @Published var hbt: Double = 160
        @Published var saveSettings: Bool = false

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() async {
            units = await settingsManager.settings.units
            presets = await storage.presets()
            maxValue = await settingsManager.preferences.autosensMax
            hbt = await storage.lastHalfBasalTarget() ?? 160
        }

        func enact() {
            Task {
                guard duration > 0 else {
                    return
                }
                var lowTarget = low

                if viewPercantage {
                    lowTarget = Decimal(round(Double(computeTarget())))
                    saveSettings = true
                }
                var highTarget = lowTarget

                if units == .mmolL, !viewPercantage {
                    lowTarget = Decimal(round(Double(lowTarget.asMgdL)))
                    highTarget = lowTarget
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
                await storage.enactTempTarget(entry, hbt: viewPercantage ? hbt : nil)
                showModal(for: nil)
            }
        }

        func cancel() {
            Task {
                await storage.cancelTempTarget()
                showModal(for: nil)
            }
        }

        func save() {
            Task {
                guard duration > 0 else {
                    return
                }
                var lowTarget = low

                if viewPercantage {
                    lowTarget = Decimal(round(Double(computeTarget())))
                    saveSettings = true
                }
                var highTarget = lowTarget

                if units == .mmolL, !viewPercantage {
                    lowTarget = Decimal(round(Double(lowTarget.asMgdL)))
                    highTarget = lowTarget
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
                await storage.storePreset(entry, hbt: viewPercantage ? hbt : nil)
            }
        }

        func enactPreset(id: String) {
            Task {
                await storage.enactPreset(id: id)
                showModal(for: nil)
            }
        }

        func removePreset(id: String) {
            Task {
                presets = presets.filter { $0.id != id }
                await storage.removePreset(id: id)
            }
        }

        func computeTarget() -> Decimal {
            var ratio = Decimal(percentage / 100)
            let c = Decimal(hbt - 100)
            var target = (c / ratio) - c + 100

            if c * (c + target - 100) <= 0 {
                ratio = maxValue
                target = (c / ratio) - c + 100
            }
            return Decimal(Double(target))
        }
    }
}
