import SwiftUI

extension Login {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            VStack {
                Text("Disclaimer").font(.title)
                Spacer()
                Text(
                    "FreeAPS X is in an active development state. We do not recommend to use the system for everyday control of blood glucose! Use it for testing purposes only at your own risk. We are not responsible for your decisions and actions."
                )
                Spacer()
                Button(action: viewModel.login) {
                    Text("Agree and continue")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .buttonBackground()
                }
            }.padding()
        }
    }
}
