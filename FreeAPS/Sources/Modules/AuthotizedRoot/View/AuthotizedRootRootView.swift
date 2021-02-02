import SwiftUI

extension AuthotizedRoot {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            TabView(selection: $viewModel.selectedTab) {
                ForEach(viewModel.tabs) { tab in
                    NavigationView {
                        tab.view
                    }
                    .tabItem {
                        VStack {
                            tab.image
                            tab.text
                        }
                    }
                    .tag(tab.id)
                }
            }
        }
    }
}
