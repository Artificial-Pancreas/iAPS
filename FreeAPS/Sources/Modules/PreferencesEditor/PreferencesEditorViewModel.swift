import SwiftUI

extension PreferencesEditor {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: PreferencesEditorProvider {
        override func subscribe() {}
    }
}
