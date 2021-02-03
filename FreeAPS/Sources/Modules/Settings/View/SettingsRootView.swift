import SwiftUI

extension Settings {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            VStack {
                Text("Settings screen")
                Button(action: viewModel.openProfileEditor) {
                    Text("Open Editor")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .buttonBackground()
                }
                Spacer()
            }
            .padding()
            .toolbar { ToolbarItem(placement: .principal) { Text("Settings") } }
        }
    }
}
