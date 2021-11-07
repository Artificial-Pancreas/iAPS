import SwiftUI
import Swinject

extension ConfigEditor {
    final class StateModel: BaseStateModel<Provider> {
        var file: String = ""
        @Published var configText = ""

        override func subscribe() {
            configText = provider.load(file: file)
        }

        func save() {
            provider.save(configText, as: file)
        }
    }
}
