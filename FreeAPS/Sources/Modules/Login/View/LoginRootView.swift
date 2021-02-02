import AuthenticationServices
import SwiftUI

extension Login {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            VStack {
                Text("FreeAPS").font(.largeTitle)
                Spacer()
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                }
                onCompletion: { result in
                    switch result {
                    case let .success(authorisation):
                        viewModel.credentials = authorisation.credential as? ASAuthorizationAppleIDCredential
                    case .failure:
                        viewModel.credentials = nil
                    }
                }
                .frame(width: 300, height: 50)
                .signInWithAppleButtonStyle(.whiteOutline)
                Spacer()
            }.padding()
        }
    }
}
