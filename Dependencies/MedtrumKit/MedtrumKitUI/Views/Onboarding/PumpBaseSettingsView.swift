import LoopKitUI
import SwiftUI

struct PumpBaseSettingsView: View {
    @State private var isShowingDeleteConfirmation: Bool = false
    @ObservedObject var viewModel: PumpBaseSettingsViewModel

    @Environment(\.guidanceColors) private var guidanceColors

    var body: some View {
        VStack {
            List {
                Section {
                    PumpImage(is300u: viewModel.is300u)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(LocalizedString("Serial number", comment: "Label for serial number"))
                                .foregroundStyle(.primary)
                            Spacer()
                            TextField("1234ABCD", text: $viewModel.serialNumber)
                                .multilineTextAlignment(.trailing)
                        }
                        Text(LocalizedString(
                            "Make sure the Serial Number is correct before connecting it to the patch.",
                            comment: "Label for checking SN"
                        ))
                            .padding(.top, 10)
                            .foregroundStyle(.primary)
                    }
                }
            }
            Spacer()
            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .foregroundStyle(.red)
            }

            Button(action: { viewModel.saveAndContinue() }) {
                Text(LocalizedString("Save and continue", comment: "save and continue"))
            }
            .disabled(viewModel.serialNumber.count != 8)
            .buttonStyle(ActionButtonStyle())
            .padding([.bottom, .horizontal])
        }
        .listStyle(InsetGroupedListStyle())
        .edgesIgnoringSafeArea(.bottom)
        .navigationTitle(LocalizedString("Pump base settings", comment: "Pump base settings header"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    isShowingDeleteConfirmation = true
                }) {
                    Text(LocalizedString("Delete Pump", comment: "Label for PumpManager deletion button"))
                        .foregroundStyle(guidanceColors.critical)
                }
                .actionSheet(isPresented: $isShowingDeleteConfirmation) {
                    removePumpManagerActionSheet(deleteAction: viewModel.pumpRemovalAction)
                }
            }
        }
    }
}
