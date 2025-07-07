import LoopKitUI
import SwiftUI

struct OnboardingWelcomeView: View {
    let nextStep: () -> Void

    var body: some View {
        VStack {
            List {
                Section {
                    PumpImage(is300u: false)
                    Text(LocalizedString(
                        "You will start by setting up your insulin type & basic patch settings before activating your patch.",
                        comment: "Welcome text for MedtrumKit"
                    ))
                }
            }
            Spacer()

            Button(action: { nextStep() }) {
                Text(LocalizedString("Continue", comment: "Continue"))
            }
            .buttonStyle(ActionButtonStyle())
            .padding([.bottom, .horizontal])
        }
        .listStyle(InsetGroupedListStyle())
        .edgesIgnoringSafeArea(.bottom)
        .navigationTitle(LocalizedString("Welcome", comment: "welcome header"))
    }
}
