import Combine
import Foundation
import LoopKit
import Swinject

extension ProfilePicker {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var keychain: Keychain!
        @Injected() var storage: FileStorage!
        @Injected() var apsManager: APSManager!

        @Published var name: String = ""
        @Published var backup: Bool = false

        let coreData = CoreDataStorage()

        func save(_ name: String) {
            coreData.saveProfileSettingName(name: name)
        }

        func saveFile(_ file: JSON, filename: String) {
            let s = BaseFileStorage()
            s.save(file, as: filename)
        }

        func apsM(resolver: Resolver) -> APSManager! {
            let a = BaseAPSManager(resolver: resolver)
            return a
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
