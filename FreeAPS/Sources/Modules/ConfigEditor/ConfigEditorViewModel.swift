import SwiftUI

extension ConfigEditor {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: ConfigEditorProvider {
        @Published var configText = ""

        override func subscribe() {
            let prefs = Preferences()
            configText = prefs.prettyPrinted
        }

        func save() {
            // TODO:
        }
    }
}
