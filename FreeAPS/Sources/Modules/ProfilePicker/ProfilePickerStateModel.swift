import Foundation
import Swinject

extension ProfilePicker {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var keychain: Keychain!
        @Injected() var storage: FileStorage!

        @Published var name: String = ""
        @Published var backup: Bool = false

        let coreData = CoreDataStorage()

        func save(_ name_: String) {
            coreData.saveProfileSettingName(name: name_)
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

        func deleteProfileFromDatabase(name: String) {
            let database = Database(token: getIdentifier())

            database.deleteProfile(name)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Profiles \(name) deleted from database")

                    case let .failure(error):
                        debug(.service, "Failed deleting \(name) from database. " + error.localizedDescription)
                    }
                }
            receiveValue: {}
                .store(in: &lifetime)
        }
    }
}
