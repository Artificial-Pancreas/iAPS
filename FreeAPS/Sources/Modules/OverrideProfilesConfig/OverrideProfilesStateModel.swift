import CoreData
import SwiftUI

extension OverrideProfilesConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var percentage: Double = 100
        @Published var isEnabled = false
        @Published var _indefinite = true
        @Published var duration: Decimal = 0
        @Published var target: Decimal = 0
        @Published var override_target: Bool = false

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
        }

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        func saveSettings() {
            coredataContext.perform { [self] in
                let saveOverride = Override(context: self.coredataContext)
                saveOverride.duration = self.duration as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentage
                saveOverride.enabled = self.isEnabled
                saveOverride.date = Date()
                if override_target {
                    if units == .mmolL {
                        target = target.asMgdL
                    }
                    saveOverride.target = target as NSDecimalNumber
                } else { saveOverride.target = 0 }
                try? self.coredataContext.save()
            }
        }

        func savedSettings() {
            coredataContext.performAndWait {
                var overrideArray = [Override]()
                let requestEnabled = Override.fetchRequest() as NSFetchRequest<Override>
                let sortIsEnabled = NSSortDescriptor(key: "date", ascending: false)
                requestEnabled.sortDescriptors = [sortIsEnabled]
                requestEnabled.fetchLimit = 1
                try? overrideArray = coredataContext.fetch(requestEnabled)
                isEnabled = overrideArray.first?.enabled ?? false
                percentage = overrideArray.first?.percentage ?? 100
                _indefinite = overrideArray.first?.indefinite ?? true
                duration = (overrideArray.first?.duration ?? 0) as Decimal
                let overrideTarget = (overrideArray.first?.target ?? 0) as Decimal

                var newDuration = Double(duration)
                if isEnabled {
                    let duration = overrideArray.first?.duration ?? 0
                    let addedMinutes = Int(duration as Decimal)
                    let date = overrideArray.first?.date ?? Date()
                    if date.addingTimeInterval(addedMinutes.minutes.timeInterval) < Date(), !_indefinite {
                        isEnabled = false
                    }
                    newDuration = Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes
                    if overrideTarget != 0 {
                        override_target = true
                        target = units == .mmolL ? overrideTarget.asMmolL : overrideTarget
                    }
                }

                if newDuration < 0 { newDuration = 0 } else { duration = Decimal(newDuration) }

                if !isEnabled {
                    _indefinite = true
                    percentage = 100
                    duration = 0
                    target = 0
                    override_target = false
                }
            }
        }
    }
}
