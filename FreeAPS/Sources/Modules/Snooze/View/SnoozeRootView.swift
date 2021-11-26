import SwiftUI
import Swinject

extension Snooze {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Text("Snooze root view")
                .navigationBarTitle("Snooze Alerts")
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear(perform: configureView)
        }
    }
}
