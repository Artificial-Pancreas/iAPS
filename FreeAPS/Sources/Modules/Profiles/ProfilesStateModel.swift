import Foundation
import Swinject

extension Profiles {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var keychain: Keychain!

        @Injected() var storage: FileStorage!
        @Injected() var apsManager: APSManager!

        @Published var name: String = ""
        @Published var backup: Bool = false

        let coreData = CoreDataStorage()

        func save(_ name: String) {
            coreData.saveProfileSettingName(name: name)
        }

        override func subscribe() {
            backup = settingsManager.settings.uploadStats
        }

        func getIdentifier() -> String {
            var identfier = keychain.getValue(String.self, forKey: IAPSconfig.id) ?? ""
            guard identfier.count > 1 else {
                identfier = UUID().uuidString
                keychain.setValue(identfier, forKey: IAPSconfig.id)
                return identfier
            }
            return identfier
        }

        func activeProfile(_ selectedProfile: String) {
            coreData.activeProfile(name: selectedProfile)
        }
    }
}
