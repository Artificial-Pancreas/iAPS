import LibreTransmitter
import SwiftUI
import Swinject

extension LibreConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @EnvironmentObject var appDelegate: AppDelegate

        var body: some View {
            Group {
                if state.configured, let manager = state.source.manager {
                    LibreTransmitterSettingsView(
                        manager: manager,
                        openSnooze: appDelegate.notificationAction == .snoozeAlert,
                        glucoseUnit: state.unit
                    ) {
                        self.state.source.manager = nil
                        self.state.configured = false
                    } completion: {
                        state.hideModal()
                    }
                    .onAppear {
                        appDelegate.notificationAction = nil
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
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .onAppear(perform: configureView)
        }
    }
}
