import SwiftUI

extension Home {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            VStack {
                Spacer()
                Button(action: viewModel.runOpenAPS) {
                    Text("Run test")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .buttonBackground()
                }
                Spacer()
            }
            .padding()
            .navigationBarTitle("Home")
        }
    }
}
