import LoopKitUI
import SwiftUI

struct PatchPrimingView: View {
    @ObservedObject var viewModel: PatchPrimingViewModel

    var body: some View {
        VStack {
            List {
                Section {
                    supportImage("connect_base")
                    HStack(alignment: .top) {
                        Text("1.")
                            .foregroundStyle(.primary)
                        Text(LocalizedString("Connect your pump base to the patch.", comment: "Label for prime step 2.1"))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section {
                    supportImage("fill_reservoir")
                    VStack(alignment: .leading) {
                        HStack(alignment: .top) {
                            Text("2.")
                                .foregroundStyle(.primary)
                            Text(LocalizedString("Fill the syringe with insulin", comment: "Label for prime step 2.2"))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top) {
                            Text("3.")
                                .foregroundStyle(.primary)
                            Text(LocalizedString(
                                "Place the syringe in the patch and pull out 1 to 2 dashes of air.",
                                comment: "Label for prime step 2.3"
                            ))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top) {
                            Text("4.")
                                .foregroundStyle(.primary)
                            Text(LocalizedString(
                                "Fill the patch with insulin. NOTE: A minimum of 70U is required for activation.",
                                comment: "Label for prime step 2.4"
                            ))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Section {
                    supportImage("half_press_needle_button")
                    HStack(alignment: .top) {
                        Text("5.")
                            .foregroundStyle(.primary)
                        Text(LocalizedString(
                            "Press the needle button and start the priming process.",
                            comment: "Label for pressing needle button step 2.5"
                        ))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer()
            if !viewModel.primingError.isEmpty {
                Text(viewModel.primingError)
                    .foregroundStyle(.red)
            } else if !viewModel.isPriming {
                Text(LocalizedString("Do not attach the patch to the body yet", comment: "Label for warning priming"))
                    .foregroundStyle(.red)
            } else {
                ProgressView(progress: viewModel.primeProgress)
                    .padding(.horizontal)
            }

            Button(action: { viewModel.previousStep() }) {
                Text(LocalizedString("Go back to pump base", comment: "label for go to pump base patch"))
            }
            .buttonStyle(ActionButtonStyle(.secondary))
            .disabled(viewModel.isPriming)
            .padding(.horizontal)

            Button(action: { viewModel.startPrime() }) {
                if viewModel.isPriming {
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                } else {
                    Text(LocalizedString("Start priming", comment: "label for prime start action"))
                }
            }
            .disabled(viewModel.isPriming)
            .buttonStyle(ActionButtonStyle())
            .padding([.bottom, .horizontal])
        }
        .listStyle(InsetGroupedListStyle())
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarBackButtonHidden(viewModel.isPriming)
        .navigationTitle(LocalizedString("Patch priming", comment: "Priming header"))
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
