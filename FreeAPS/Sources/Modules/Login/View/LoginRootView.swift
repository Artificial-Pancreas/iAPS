import SwiftUI

extension Login {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            VStack {
                Text("Disclaimer").font(.title)
                Spacer()
                Button(action: viewModel.login) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .buttonBackground()
                }
            }.padding()
        }
    }
}
