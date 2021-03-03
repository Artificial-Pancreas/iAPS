import SwiftUI

extension TargetsEditor {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: TargetsEditorProvider {
        override func subscribe() {}
    }
}
