import Swinject

extension ConfigEditor {
    final class Builder: BaseModuleBuilder<RootView, ViewModel<Provider>, Provider> {
        private let file: String

        init(resolver: Resolver, file: String) {
            self.file = file
            super.init(resolver: resolver)
        }

        override func buildViewModel() -> ConfigEditor.ViewModel<ConfigEditor.Provider> {
            ViewModel(provider: Provider(resolver: resolver), resolver: resolver, file: file)
        }
    }
}
