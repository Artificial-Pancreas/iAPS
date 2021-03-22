import SwiftDate
import SwiftUI

extension Home {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>
        @State var isStatusPopupPresented = false

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
                LoopView(
                    suggestion: $viewModel.suggestion,
                    enactedSuggestion: $viewModel.enactedSuggestion,
                    closedLoop: $viewModel.closedLoop,
                    timerDate: $viewModel.timerDate,
                    isLooping: $viewModel.isLooping
                ).onTapGesture {
                    isStatusPopupPresented = true
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
                        tempBasals: $viewModel.tempBasals,
                        boluses: $viewModel.boluses,
                        hours: .constant(viewModel.filteredHours),
                        maxBasal: $viewModel.maxBasal,
                        basalProfile: $viewModel.basalProfile,
                        tempTargets: $viewModel.tempTargets,
                        carbs: $viewModel.carbs,
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
            .popup(isPresented: isStatusPopupPresented, alignment: .top, direction: .top) {
                VStack(alignment: .leading) {
                    Text(viewModel.statusTitle).foregroundColor(.white)
                        .padding(.bottom, 4)
                    Text(viewModel.suggestion?.reason ?? "No sugestion found").font(.caption).foregroundColor(.white)
                }
                .padding()

                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(UIColor.darkGray))
                )
                .onTapGesture {
                    isStatusPopupPresented = false
                }
            }
        }
    }
}
