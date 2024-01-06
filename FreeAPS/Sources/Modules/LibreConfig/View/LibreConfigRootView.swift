import LibreTransmitter
import SwiftUI
import Swinject

extension LibreConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Group {
                if state.configured, let manager = state.source.manager {
                    LibreTransmitterSettingsView(
                        manager: manager,
                        glucoseUnit: state.unit
                    ) {
                        self.state.source.manager = nil
                        self.state.configured = false
                    } completion: {
                        state.hideModal()
                    }
                } else {
                    LibreTransmitterSetupView { manager in
                        self.state.source.manager = manager
                        self.state.configured = true
                    } completion: {
                        state.hideModal()
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .onAppear(perform: configureView)
        }
    }
}
