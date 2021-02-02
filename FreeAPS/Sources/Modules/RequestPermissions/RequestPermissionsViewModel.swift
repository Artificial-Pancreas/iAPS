import SwiftUI

extension RequestPermissions {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: RequestPermissionsProvider {}
}
