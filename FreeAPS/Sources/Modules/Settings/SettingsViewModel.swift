import SwiftUI

extension Settings {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: SettingsProvider {
        func openProfileEditor() {
            router.modalScreen.send(.configEditor)
        }
    }
}
