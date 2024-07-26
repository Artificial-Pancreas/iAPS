import Foundation
import Swinject

extension ProfilePicker {
    final class StateModel: BaseStateModel<Provider> {
        // @Injected() var keychain: Keychain!

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
            Token().getIdentifier()
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
