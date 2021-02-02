import SwiftUI

extension Onboarding {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            viewModel.view(for: viewModel.stage.screen)
        }
    }
}
