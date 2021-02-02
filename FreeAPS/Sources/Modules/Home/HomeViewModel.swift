import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        func runOpenAPS() {
            OpenAPS().test()
        }
    }
}
