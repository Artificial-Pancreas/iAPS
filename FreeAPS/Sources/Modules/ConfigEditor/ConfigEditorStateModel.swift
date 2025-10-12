import SwiftUI
import Swinject

extension ConfigEditor {
    final class StateModel: BaseStateModel<Provider> {
        let file: String
        @Published var configText = ""

        init(resolver: Resolver, file: String) {
            self.file = file
            super.init(resolver: resolver)
        }

        override func subscribe() {
            configText = provider.load(file: file)
        }

        func save() {
            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            impactHeavy.impactOccurred()
            provider.save(configText, as: file)
        }
    }
}
