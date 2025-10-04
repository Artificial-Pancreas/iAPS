import SwiftUI
import Swinject

extension IconConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            IconSelection()
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }
}
