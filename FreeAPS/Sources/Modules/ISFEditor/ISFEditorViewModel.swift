import SwiftUI

extension ISFEditor {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: ISFEditorProvider {
        override func subscribe() {}
    }
}
