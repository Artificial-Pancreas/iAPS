import SwiftDate
import SwiftUI

extension Home {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>
        @State var isPopupPresented = false

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var header: some View {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text("IOB").font(.caption)
                        Text((numberFormatter.string(from: (viewModel.suggestion?.iob ?? 0) as NSNumber) ?? "0") + " U")
                            .font(.caption2)
                    }.padding(.top, 16)
                    Spacer()
                    HStack {
                        Text("COB").font(.caption)
                        Text((numberFormatter.string(from: (viewModel.suggestion?.cob ?? 0) as NSNumber) ?? "0") + " g")
                            .font(.caption2)
                    }
                }
                Spacer()
                CurrentGlucoseView(
                    recentGlucose: $viewModel.recentGlucose,
                    delta: $viewModel.glucoseDelta,
                    units: viewModel.units
                )
                .padding(.horizontal)
                LoopView(suggestion: $viewModel.suggestion).onTapGesture {
                    isPopupPresented = true
                }.onLongPressGesture {
                    viewModel.runLoop()
                }
            }.frame(maxWidth: .infinity)
        }

        var body: some View {
            viewModel.setFilteredGlucoseHours(hours: 24)
            return GeometryReader { geo in
                VStack {
                    header.padding().frame(maxHeight: 70)
                    MainChartView(
                        glucose: $viewModel.glucose,
                        suggestion: $viewModel.suggestion,
                        basals: $viewModel.basals,
                        hours: .constant(viewModel.filteredHours),
                        maxBasal: $viewModel.maxBasal,
                        units: viewModel.units
                    )

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
            .ignoresSafeArea(.keyboard)
            .popup(isPresented: isPopupPresented, alignment: .top, direction: .top) {
                Text(viewModel.suggestion?.reason ?? "No sugestion found").font(.caption).padding().foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(UIColor.darkGray))
                    )
                    .onTapGesture {
                        isPopupPresented = false
                    }
            }
        }
    }
}
