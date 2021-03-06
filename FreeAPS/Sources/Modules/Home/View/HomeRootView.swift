import SwiftUI

extension Home {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
                GlucoseChartView(glucose: $viewModel.glucose).frame(height: 150)
                Button(action: viewModel.addCarbs) {
                    Text("Add carbs")
                }
                Button(action: viewModel.addTempTarget) {
                    Text("Add temp target")
                }
                Button(action: viewModel.bolus) {
                    Text("Bolus")
                }
                Button(action: viewModel.runLoop) {
                    Text("Run loop")
                }
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
        }
    }
}
