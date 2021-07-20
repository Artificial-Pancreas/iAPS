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

        private var targetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            return dateFormatter
        }

        var header: some View {
            HStack(alignment: .bottom) {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("IOB").font(.caption2).foregroundColor(.secondary)
                        Text(
                            (numberFormatter.string(from: (viewModel.suggestion?.iob ?? 0) as NSNumber) ?? "0") +
                                NSLocalizedString(" U", comment: "Insulin unit")
                        )
                        .font(.system(size: 12, weight: .bold))
                    }
                    HStack {
                        Text("COB").font(.caption2).foregroundColor(.secondary)
                        Text(
                            (numberFormatter.string(from: (viewModel.suggestion?.cob ?? 0) as NSNumber) ?? "0") +
                                NSLocalizedString(" g", comment: "gram of carbs")
                        )
                        .font(.system(size: 12, weight: .bold))
                    }
                }
                Spacer()

                CurrentGlucoseView(
                    recentGlucose: $viewModel.recentGlucose,
                    delta: $viewModel.glucoseDelta,
                    units: $viewModel.units
                )
                .onTapGesture {
                    viewModel.openCGM()
                }
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
            HStack(alignment: .center) {
                if viewModel.pumpSuspended {
                    Text("Pump suspended")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.loopGray)
                        .padding(.leading, 8)
                } else if let tempRate = viewModel.tempRate {
                    Text(
                        (numberFormatter.string(from: tempRate as NSNumber) ?? "0") +
                            NSLocalizedString(" U/hr", comment: "Unit per hour with space")
                    )
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                    .padding(.leading, 8)
                }

                if let tempTarget = viewModel.tempTarget {
                    Text(tempTarget.displayName).font(.caption).foregroundColor(.secondary)
                    if viewModel.units == .mmolL {
                        Text(
                            targetFormatter
                                .string(from: (tempTarget.targetBottom?.asMmolL ?? 0) as NSNumber)!
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        if tempTarget.targetBottom != tempTarget.targetTop {
                            Text("-").font(.caption)
                                .foregroundColor(.secondary)
                            Text(
                                targetFormatter
                                    .string(from: (tempTarget.targetTop?.asMmolL ?? 0) as NSNumber)! +
                                    " \(viewModel.units.rawValue)"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        } else {
                            Text(viewModel.units.rawValue).font(.caption)
                                .foregroundColor(.secondary)
                        }

                    } else {
                        Text(targetFormatter.string(from: (tempTarget.targetBottom ?? 0) as NSNumber)!)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if tempTarget.targetBottom != tempTarget.targetTop {
                            Text("-").font(.caption)
                                .foregroundColor(.secondary)
                            Text(
                                targetFormatter
                                    .string(from: (tempTarget.targetTop ?? 0) as NSNumber)! + " \(viewModel.units.rawValue)"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        } else {
                            Text(viewModel.units.rawValue).font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                if let progress = viewModel.bolusProgress {
                    Text("Bolusing")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                    ProgressView(value: Double(progress))
                        .progressViewStyle(BolusProgressViewStyle())
                        .padding(.trailing, 8)
                        .onTapGesture {
                            viewModel.cancelBolus()
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 30)
        }

        var legendPanal: some View {
            HStack(alignment: .center) {
                Group {
                    Circle().fill(Color.loopGreen).frame(width: 8, height: 8)
                    Text("BG")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.loopGreen)
                }
                Group {
                    Circle().fill(Color.insulin).frame(width: 8, height: 8)
                        .padding(.leading, 8)
                    Text("IOB")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                }
                Group {
                    Circle().fill(Color.zt).frame(width: 8, height: 8)
                        .padding(.leading, 8)
                    Text("ZT")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.zt)
                }
                Group {
                    Circle().fill(Color.loopYellow).frame(width: 8, height: 8)
                        .padding(.leading, 8)
                    Text("COB")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.loopYellow)
                }
                Group {
                    Circle().fill(Color.uam).frame(width: 8, height: 8)
                        .padding(.leading, 8)
                    Text("UAM")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.uam)
                }

                if let eventualBG = viewModel.eventualBG {
                    Text(
                        "⇢ " + numberFormatter.string(
                            from: (viewModel.units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
                        )!
                    )
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                }
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
                        suspensions: $viewModel.suspensions,
                        hours: .constant(viewModel.filteredHours),
                        maxBasal: $viewModel.maxBasal,
                        autotunedBasalProfile: $viewModel.autotunedBasalProfile,
                        basalProfile: $viewModel.basalProfile,
                        tempTargets: $viewModel.tempTargets,
                        carbs: $viewModel.carbs,
                        timerDate: $viewModel.timerDate,
                        units: $viewModel.units
                    )
                    .padding(.bottom)
                    .modal(for: .dataTable, from: self)

                    legendPanal

                    ZStack {
                        Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 50 + geo.safeAreaInsets.bottom)

                        HStack {
                            Button { viewModel.showModal(for: .addCarbs) }
                            label: {
                                ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                                    Image("carbs")
                                        .renderingMode(.template)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(.loopGreen)
                                        .padding(8)
                                    if let carbsReq = viewModel.carbsRequired {
                                        Text(numberFormatter.string(from: carbsReq as NSNumber)!)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .background(Capsule().fill(Color.red))
                                    }
                                }
                            }
                            Spacer()
                            Button { viewModel.showModal(for: .addTempTarget) }
                            label: {
                                Image("target")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .padding(8)
                            }.foregroundColor(.loopYellow)
                            Spacer()
                            Button { viewModel.showModal(for: .bolus(waitForDuggestion: false)) }
                            label: {
                                Image("bolus")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .padding(8)
                            }.foregroundColor(.insulin)
                            Spacer()
                            if viewModel.allowManualTemp {
                                Button { viewModel.showModal(for: .manualTempBasal) }
                                label: {
                                    Image("bolus1")
                                        .renderingMode(.template)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                        .padding(8)
                                }.foregroundColor(.insulin)
                                Spacer()
                            }
                            Button { viewModel.showModal(for: .settings) }
                            label: {
                                Image("settings1")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .padding(8)
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

                    if let errorMessage = viewModel.errorMessage, let date = viewModel.errorDate {
                        Text("Error at \(dateFormatter.string(from: date))").foregroundColor(.white)
                            .padding(.bottom, 4)
                            .padding(.top, 8)
                        Text(errorMessage).font(.caption).foregroundColor(.white)
                    }
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
