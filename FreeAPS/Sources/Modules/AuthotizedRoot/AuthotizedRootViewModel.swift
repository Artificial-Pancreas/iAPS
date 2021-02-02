import SwiftUI
import Swinject

extension AuthotizedRoot {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AuthotizedRootProvider {
        @Published private(set) var tabs: [Tab] = []
        @Published var selectedTab = Config.initialTab
        @Published private(set) var isAuthotized = true

        required init(provider: Provider, resolver: Resolver) {
            super.init(provider: provider, resolver: resolver)
            setupTabs()
        }

        private func setupTabs() {
            tabs = router.tabs.map { $0.tab(resolver: self.resolver) }
        }

        override func subscribe() {
            router.selectTab
                .receive(on: RunLoop.main)
                .assign(to: \.selectedTab, on: self)
                .store(in: &lifetime)
        }
    }
}
