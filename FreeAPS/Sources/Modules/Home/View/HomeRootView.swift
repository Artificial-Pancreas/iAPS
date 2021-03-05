import SwiftUI

extension Home {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            VStack {
                Spacer()
                Button(action: viewModel.addCarbs) {
                    Text("Add carbs")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .buttonBackground()
                }
                Button(action: viewModel.addHighTempTarget) {
                    Text("Temp target 7.0 mmol/L for 10 min")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .buttonBackground()
                }
                Button(action: viewModel.addLowTempTarget) {
                    Text("Temp target 4.5 mmol/L for 10 min")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .buttonBackground()
                }
                Button(action: viewModel.runLoop) {
                    Text("Run loop")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .buttonBackground()
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
