import Foundation
import SwiftUI
import Swinject

extension Restore {
    final class StateModel: BaseStateModel<Provider> {
        @Published var name: String = ""
        @Published var backup: Bool = false
        @Published var basalsSaved = false

        /*
         @Published var glucoseBadge = false
         @Published var glucoseNotificationsAlways = false
         @Published var useAlarmSound = false
         @Published var addSourceInfoToGlucoseNotifications = false
         @Published var lowGlucose: Decimal = 0
         @Published var highGlucose: Decimal = 0
         @Published var carbsRequiredThreshold: Decimal = 0
         @Published var useLiveActivity = false
         @Published var units: GlucoseUnits = .mmolL
         @Published var closedLoop = false*/

        let coreData = CoreDataStorage()
        let overrrides = OverrideStorage()
        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() {
            backup = settingsManager.settings.uploadStats
        }

        func save(_ name: String) {
            coreData.saveProfileSettingName(name: name)
        }

        func saveFile(_ file: JSON, filename: String) {
            let s = BaseFileStorage()
            s.save(file, as: filename)
        }

        func activeProfile(_ selectedProfile: String) {
            coreData.activeProfile(name: selectedProfile)
        }

        func fetchSettingProfileNames() -> [Profiles]? {
            coreData.fetchSettingProfileNames()
        }

        func saveMealPresets(_ mealPresets: [MigratedMeals]) {
            coredataContext.performAndWait {
                for item in mealPresets {
                    let saveToCoreData = Presets(context: self.coredataContext)
                    saveToCoreData.dish = item.dish
                    saveToCoreData.carbs = item.carbs as NSDecimalNumber
                    saveToCoreData.fat = item.fat as NSDecimalNumber
                    saveToCoreData.protein = item.protein as NSDecimalNumber
                }
                try? self.coredataContext.save()
            }
        }

        func saveOverridePresets(_ presets: [MigratedOverridePresets]) {
            coredataContext.performAndWait {
                for item in presets {
                    let saveToCoreData = OverridePresets(context: self.coredataContext)
                    saveToCoreData.percentage = item.percentage
                    saveToCoreData.target = item.target as NSDecimalNumber
                    saveToCoreData.end = item.end as NSDecimalNumber
                    saveToCoreData.start = item.start as NSDecimalNumber
                    saveToCoreData.id = item.id
                    saveToCoreData.advancedSettings = item.advancedSettings
                    saveToCoreData.cr = item.cr
                    saveToCoreData.duration = item.duration as NSDecimalNumber
                    saveToCoreData.isf = item.isf
                    saveToCoreData.name = item.name
                    saveToCoreData.isfAndCr = item.isndAndCr
                    saveToCoreData.smbIsAlwaysOff = item.smbAlwaysOff
                    saveToCoreData.smbIsOff = item.smbIsOff
                    saveToCoreData.smbMinutes = item.smbMinutes as NSDecimalNumber
                    saveToCoreData.uamMinutes = item.uamMinutes as NSDecimalNumber
                    saveToCoreData.date = item.date
                    saveToCoreData.maxIOB = item.maxIOB as NSDecimalNumber
                    saveToCoreData.overrideMaxIOB = item.overrideMaxIOB
                }
                try? self.coredataContext.save()
            }
        }

        func getIdentifier() -> String {
            Token().getIdentifier()
        }
    }
}
