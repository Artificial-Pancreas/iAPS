import LoopKitUI
import SwiftUI

struct PatchActivationView: View {
    @ObservedObject var viewModel: PatchActivationViewModel

    var body: some View {
        VStack {
            List {
                Section {
                    supportImage("remove_cover")
                    HStack(alignment: .top) {
                        Text("6.")
                            .foregroundStyle(.primary)
                        Text(LocalizedString(
                            "Remove the safety cover from the patch.",
                            comment: "Label for inserting needle step 1"
                        ))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section {
                    supportImage("attach_body")
                    HStack(alignment: .top) {
                        Text("7.")
                            .foregroundStyle(.primary)
                        Text(LocalizedString("Attach the pump to the body.", comment: "Label for inserting needle step 2"))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section {
                    supportImage("needle_insert")
                    HStack(alignment: .top) {
                        Text("8.")
                            .foregroundStyle(.primary)
                        Text(LocalizedString(
                            "Press the needle button to insert the needle. Click on \"Activate\" to complete the activation process.",
                            comment: "Label for inserting needle step 3"
                        ))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer()
            if !viewModel.activationError.isEmpty {
                Text(viewModel.activationError)
                    .foregroundStyle(.red)
            }

            Button(action: { viewModel.previousStep() }) {
                Text(LocalizedString("Go back to priming", comment: "label for go to prime patch"))
            }
            .buttonStyle(ActionButtonStyle(.secondary))
            .disabled(viewModel.isActivating)
            .padding(.horizontal)

            Button(action: { viewModel.activate() }) {
                if viewModel.isActivating {
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                } else {
                    Text(LocalizedString("Activate patch", comment: "label for activate patch"))
                }
            }
            .disabled(viewModel.isActivating)
            .buttonStyle(ActionButtonStyle())
            .padding([.bottom, .horizontal])
        }
        .listStyle(InsetGroupedListStyle())
        .edgesIgnoringSafeArea(.bottom)
        .navigationTitle(LocalizedString("Patch activation", comment: "Patch activation header"))
    }

    @ViewBuilder func supportImage(_ imageName: String) -> some View {
        HStack {
            Spacer()
            Image(uiImage: UIImage(named: imageName, in: Bundle(for: MedtrumKitHUDProvider.self), compatibleWith: nil)!)
                .resizable()
                .scaledToFit()
                .padding(.horizontal)
                .frame(height: 100)
            Spacer()
        }
    }
}
