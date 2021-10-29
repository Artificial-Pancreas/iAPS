import SwiftUI
import Swinject

extension AuthorizedRoot {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AuthorizedRootProvider {
        override func subscribe() {}

        lazy var rootView: some View = { router.view(for: .home) }()
    }
}
