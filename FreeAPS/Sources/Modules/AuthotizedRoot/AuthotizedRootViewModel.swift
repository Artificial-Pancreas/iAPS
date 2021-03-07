import SwiftUI
import Swinject

extension AuthotizedRoot {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AuthotizedRootProvider {
        override func subscribe() {}

        var rootView: some View {
            router.view(for: .home)
        }
    }
}
