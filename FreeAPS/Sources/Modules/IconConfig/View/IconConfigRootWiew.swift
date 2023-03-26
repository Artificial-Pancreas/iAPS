import SwiftUI
import Swinject

extension IconConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            IconSelection()
                .onAppear(perform: configureView)
        }
    }
}
