import SwiftUI

extension CREditor {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: CREditorProvider {
        override func subscribe() {}
    }
}
