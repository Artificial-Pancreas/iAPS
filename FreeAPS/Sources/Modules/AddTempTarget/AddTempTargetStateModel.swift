import CoreData
import SwiftUI

extension AddTempTarget {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var storage: TempTargetsStorage!
        @Injected() var apsManager: APSManager!

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
        @Environment(\.managedObjectContext) var moc

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

        override func subscribe() {
            units = settingsManager.settings.units
            presets = storage.presets()
            maxValue = settingsManager.preferences.autosensMax
        }

        func enact() {
            guard duration > 0 else {
                return
            }
            var lowTarget = low

            if viewPercantage {
                lowTarget = computeTarget()
                saveSettings = true
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

            coredataContext.performAndWait {
                let saveToCoreData = TempTargets(context: self.coredataContext)
                saveToCoreData.active = false
                saveToCoreData.date = Date()
                try? self.coredataContext.save()

                let setHBT = TempTargetsSlider(context: self.coredataContext)
                setHBT.enabled = false
                try? self.coredataContext.save()
            }
        }

        func save() {
            guard duration > 0 else {
                return
            }
            var lowTarget = low

            if viewPercantage {
                lowTarget = computeTarget()
                saveSettings = true
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

            if viewPercantage {
                let id = entry.id

                coredataContext.performAndWait {
                    let saveToCoreData = TempTargetsSlider(context: self.coredataContext)
                    saveToCoreData.id = id
                    saveToCoreData.isPreset = true
                    saveToCoreData.enabled = true
                    saveToCoreData.hbt = hbt
                    saveToCoreData.enabled = true
                    saveToCoreData.date = Date()
                    saveToCoreData.duration = duration as NSDecimalNumber
                    try? self.coredataContext.save()
                }
            }
        }

        func enactPreset(id: String) {
            if var preset = presets.first(where: { $0.id == id }) {
                preset.createdAt = Date()
                storage.storeTempTargets([preset])
                showModal(for: nil)

                coredataContext.performAndWait {
                    var tempTargetsArray = [TempTargetsSlider]()
                    let requestTempTargets = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
                    let sortTT = NSSortDescriptor(key: "date", ascending: false)
                    requestTempTargets.sortDescriptors = [sortTT]
                    try? tempTargetsArray = coredataContext.fetch(requestTempTargets)

                    let whichID = tempTargetsArray.first(where: { $0.id == id })

                    if whichID != nil {
                        let saveToCoreData = TempTargets(context: self.coredataContext)
                        saveToCoreData.active = true
                        saveToCoreData.date = Date()
                        saveToCoreData.hbt = whichID?.hbt ?? 160
                        // saveToCoreData.id = id
                        saveToCoreData.startDate = Date()
                        saveToCoreData.duration = whichID?.duration ?? 0

                        try? self.coredataContext.save()
                    } else {
                        let saveToCoreData = TempTargets(context: self.coredataContext)
                        saveToCoreData.active = false
                        saveToCoreData.date = Date()
                        try? self.coredataContext.save()
                    }
                }
            }
        }

        func removePreset(id: String) {
            presets = presets.filter { $0.id != id }
            storage.storePresets(presets)
        }

        func computeTarget() -> Decimal {
            var ratio = Decimal(percentage / 100)
            let c = Decimal(hbt - 100)
            var target = (c / ratio) - c + 100

            if c * (c + target - 100) <= 0 {
                ratio = maxValue
                target = (c / ratio) - c + 100
            }
            return target
        }
    }
}
