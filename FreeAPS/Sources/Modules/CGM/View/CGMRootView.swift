import SwiftUI

extension CGM {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
                Section {
                    Picker("Type", selection: $viewModel.cgm) {
                        ForEach(CGMType.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }
            }
            .navigationTitle("CGM")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
