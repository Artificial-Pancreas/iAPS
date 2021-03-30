import SwiftUI
import Swinject

extension ConfigEditor {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: ConfigEditorProvider {
        let file: String
        @Published var configText = ""

        init(provider: Provider, resolver: Resolver, file: String) {
            self.file = file
            super.init(provider: provider, resolver: resolver)
        }

        required init(provider _: Provider, resolver _: Resolver) {
            error(.default, "init(provider:resolver:) has not been implemented")
        }

        override func subscribe() {
            configText = provider.load(file: file)
        }

        func save() {
            provider.save(configText, as: file)
        }
    }
}
