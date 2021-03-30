import SwiftDate
import SwiftUI

extension Home {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>
        @State var isStatusPopupPresented = false

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var header: some View {
            HStack(alignment: .bottom) {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("IOB").font(.caption2).foregroundColor(.secondary)
                        Text((numberFormatter.string(from: (viewModel.suggestion?.iob ?? 0) as NSNumber) ?? "0") + " U")
                            .font(.system(size: 12, weight: .bold))
                    }
                    HStack {
                        Text("COB").font(.caption2).foregroundColor(.secondary)
                        Text((numberFormatter.string(from: (viewModel.suggestion?.cob ?? 0) as NSNumber) ?? "0") + " g")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                Spacer()

                CurrentGlucoseView(
                    recentGlucose: $viewModel.recentGlucose,
                    delta: $viewModel.glucoseDelta,
                    units: viewModel.units
                )
                Spacer()
                PumpView(
                    reservoir: $viewModel.reservoir,
                    battery: $viewModel.battery,
                    name: $viewModel.pumpName,
                    expiresAtDate: $viewModel.pumpExpiresAtDate,
                    timerDate: $viewModel.timerDate
                )
                .onTapGesture {
                    viewModel.setupPump = true
                }
                .popover(isPresented: $viewModel.setupPump) {
                    if let pumpManager = viewModel.provider.apsManager.pumpManager {
                        PumpConfig.PumpSettingsView(pumpManager: pumpManager, completionDelegate: viewModel)
                    }
                }
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
                Spacer()
            }.frame(maxWidth: .infinity)
        }

        var infoPanal: some View {
            HStack(alignment: .firstTextBaseline) {
                if let tempRate = viewModel.tempRate {
                    Text((numberFormatter.string(from: tempRate as NSNumber) ?? "0") + " U/hr")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                        .padding(.leading, 8)
                }

                if let tepmTargetName = viewModel.tempTargetName {
                    Text(tepmTargetName).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: 30)
        }

        var body: some View {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    header
                        .frame(maxHeight: 70)
                        .padding(.top, geo.safeAreaInsets.top)
                        .background(Color.gray.opacity(0.2))

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
                            }.foregroundColor(.loopGreen)
                            Spacer()
                            Button { viewModel.showModal(for: .addTempTarget) }
                            label: {
                                Image("target")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }.foregroundColor(.loopYellow)
                            Spacer()
                            Button { viewModel.showModal(for: .bolus) }
                            label: {
                                Image("bolus")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }.foregroundColor(.insulin)
                            Spacer()
                            if viewModel.allowManualTemp {
                                Button { viewModel.showModal(for: .manualTempBasal) }
                                label: {
                                    Image("bolus1")
                                        .renderingMode(.template)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }.foregroundColor(.insulin)
                                Spacer()
                            }
                            Button { viewModel.showModal(for: .settings) }
                            label: {
                                Image("settings1")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }.foregroundColor(.loopGray)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, geo.safeAreaInsets.bottom)
                    }
                }
                .edgesIgnoringSafeArea(.vertical)
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
                .gesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onEnded { value in
                            if value.translation.height < 0 {
                                isStatusPopupPresented = false
                            }
                        }
                )
            }
        }
    }
}
