import SwiftUI

extension Home {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>
        @State var showHours = 1

        var body: some View {
            viewModel.setFilteredGlucoseHours(hours: 24)
            return GeometryReader { geo in
                VStack {
                    Group {
                        Text("Header")
                    }
                    ScrollView(.vertical, showsIndicators: false) {
                        HoursPickerView(selectedHour: $showHours)
                        ScrollView(.horizontal, showsIndicators: false) {
                            PointChartView(
                                minValue: 20,
                                maxValue: 300,
                                width: geo.size.width,
                                showHours: showHours,
                                glucoseData: SampleData.sampleData
                            ) { value in
                                GlucosePointView(value: value)
                            }
                        }.frame(height: 300)

                        // GlucoseChartView(glucose: $viewModel.glucose, suggestion: $viewModel.suggestion).frame(height: 150)
                        if let reason = viewModel.suggestion?.reason {
                            Text(reason).font(.caption).padding()
                        }
                        Button(action: viewModel.runLoop) {
                            Text("Run loop now").buttonBackground().padding()
                        }.foregroundColor(.white)
                    }

                    ZStack {
                        Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 50 + geo.safeAreaInsets.bottom)

                        HStack {
                            Button { viewModel.showModal(for: .addCarbs) }
                            label: {
                                Image(systemName: "circlebadge.2.fill")
                            }.foregroundColor(.green)
                            Spacer()
                            Button { viewModel.showModal(for: .addTempTarget) }
                            label: {
                                Image(systemName: "target")
                            }.foregroundColor(.green)
                            Spacer()
                            Button { viewModel.showModal(for: .bolus) }
                            label: {
                                Image(systemName: "drop.fill")
                            }.foregroundColor(.orange)
                            Spacer()
                            if viewModel.allowManualTemp {
                                Button { viewModel.showModal(for: .manualTempBasal) }
                                label: {
                                    Image(systemName: "circle.bottomhalf.fill")
                                }.foregroundColor(.blue)
                                Spacer()
                            }
                            Button { viewModel.showModal(for: .settings) }
                            label: {
                                Image(systemName: "gearshape")
                            }.foregroundColor(.gray)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, geo.safeAreaInsets.bottom)
                    }
                }
                .edgesIgnoringSafeArea(.bottom)
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
        }
    }
}
