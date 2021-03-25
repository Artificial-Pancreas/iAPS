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
                PumpView(
                    reservoir: $viewModel.reservoir,
                    battery: $viewModel.battery,
                    name: $viewModel.pumpName,
                    expiresAtDate: $viewModel.pumpExpiresAtDate,
                    timerDate: $viewModel.timerDate
                )
                Spacer()
                CurrentGlucoseView(
                    recentGlucose: $viewModel.recentGlucose,
                    delta: $viewModel.glucoseDelta,
                    units: viewModel.units
                ).frame(minWidth: 0, maxWidth: .infinity)
                Spacer()
                LoopView(
                    suggestion: $viewModel.suggestion,
                    enactedSuggestion: $viewModel.enactedSuggestion,
                    closedLoop: $viewModel.closedLoop,
                    timerDate: $viewModel.timerDate,
                    isLooping: $viewModel.isLooping,
                    lastLoopDate: $viewModel.lastLoopDate
                ).onTapGesture {
                    isStatusPopupPresented = true
                }.onLongPressGesture {
                    viewModel.runLoop()
                }
            }.frame(maxWidth: .infinity)
        }

        var infoPanal: some View {
            HStack(alignment: .firstTextBaseline) {
                Text("IOB").font(.caption)
                    .padding(.leading)
                Text((numberFormatter.string(from: (viewModel.suggestion?.iob ?? 0) as NSNumber) ?? "0") + " U")
                    .font(.caption)

                Text("COB").font(.caption)
                Text((numberFormatter.string(from: (viewModel.suggestion?.cob ?? 0) as NSNumber) ?? "0") + " g")
                    .font(.caption)
                if let tempRate = viewModel.tempRate {
                    Text("Temp basal").font(.caption).foregroundColor(.blue)
                    Text((numberFormatter.string(from: tempRate as NSNumber) ?? "0") + " U/hr")
                        .font(.caption).foregroundColor(.blue)
                }

                Spacer()

            }.frame(maxWidth: .infinity, maxHeight: 30)
                .background(Rectangle().fill(Color.gray.opacity(0.2)))
        }

        var body: some View {
            viewModel.setFilteredGlucoseHours(hours: 24)
            return GeometryReader { geo in
                VStack(spacing: 0) {
                    header.padding(.vertical).frame(maxHeight: 70)
                    infoPanal
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
                    .padding(.bottom)

                    ZStack {
                        Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 50 + geo.safeAreaInsets.bottom)

                        HStack {
                            Button { viewModel.showModal(for: .addCarbs) }
                            label: {
                                Image("carbs")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }.foregroundColor(.orange)
                            Spacer()
                            Button { viewModel.showModal(for: .addTempTarget) }
                            label: {
                                Image("target")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }.foregroundColor(.primary)
                            Spacer()
                            Button { viewModel.showModal(for: .bolus) }
                            label: {
                                Image("bolus")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }.foregroundColor(.blue)
                            Spacer()
                            if viewModel.allowManualTemp {
                                Button { viewModel.showModal(for: .manualTempBasal) }
                                label: {
                                    Image("bolus1")
                                        .renderingMode(.template)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }.foregroundColor(.blue)
                                Spacer()
                            }
                            Button { viewModel.showModal(for: .settings) }
                            label: {
                                Image("settings1")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
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
