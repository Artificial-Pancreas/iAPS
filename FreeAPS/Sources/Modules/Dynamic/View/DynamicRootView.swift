import SwiftUI
import Swinject

extension Dynamic {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State var isPresented = false
        @State var description = Text("")
        @State var descriptionHeader = Text("")
        @State var scrollView = false
        @State var graphics: (any View)?

        @Environment(\.colorScheme) var colorScheme
        @Environment(\.sizeCategory) private var fontSize

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.unit == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var daysFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    if state.aisf {
                        Text("Dynamic ISF is disabled while Auto ISF is enabled")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundStyle(.red)
                    } else {
                        HStack {
                            Toggle(isOn: $state.useNewFormula) {
                                Text("Activate Dynamic Sensitivity (ISF)")
                                    .onTapGesture {
                                        info(
                                            header: "Activate Dynamic Sensitivity (ISF)",
                                            body: "Calculate a new Insulin Sensitivity Setting (ISF) upon every loop cycle. The new ISF will be based on your current Glucose, total daily dose of insulin (TDD, past 24 hours of all delivered insulin) and an individual Adjustment Factor (recommendation to start with is 0.5 if using Sigmoid Function and 0.8 if not).\n\nAll of the Dynamic ISF and CR adjustments will be limited by your autosens.min/max limits.",
                                            useGraphics: nil
                                        )
                                    }
                            }.disabled(isPresented)
                        }
                    }

                    if state.useNewFormula, !state.aisf {
                        HStack {
                            Toggle(isOn: $state.enableDynamicCR) {
                                Text("Activate Dynamic Carb Ratio (CR)")
                                    .onTapGesture {
                                        scrollView = fontSize >= .extraLarge ? true : false
                                        info(
                                            header: "Activate Dynamic Carb Ratio (CR)",
                                            body: "Use a Dynamic Carb Ratio (CR). The dynamic Carb Ratio will adjust your profile Carb Ratio (or your Autotuned CR if you're using Autotune) using the same dynamic adjustment as for the Dynamic Insulin Sensitivity (ISF), but with an extra safety limit.\n\n When the dynamic adjustment is > 1:  Dynamic Ratio = (dynamic adjustment - 1) / 2 + 1.\nWhen dynamic adjustment < 1: Dynamic ratio = Profile CR / dynamic adjustment.\n\nPlease don't use together with a high Insulin Fraction (> 2) or together with a high Bolus Percentage (> 120 %), as this could lead to too big bolus recommendations",
                                            useGraphics: nil
                                        )
                                    }
                            }.disabled(isPresented)
                        }
                    }
                } header: { state.aisf ? nil : Text("Experimental").foregroundStyle(.red) }

                if state.useNewFormula, !state.aisf {
                    Section {
                        HStack {
                            Toggle(isOn: $state.sigmoid) {
                                Text("Use Sigmoid Function")
                                    .onTapGesture {
                                        scrollView = true
                                        info(
                                            header: "Use Sigmoid Function",
                                            body: "Use a sigmoid function for ISF (and for CR, when enabled), instead of the default Logarithmic formula. Requires the Dynamic ISF setting to be enabled in settings\n\nThe Adjustment setting adjusts the slope of the curve (Y: Dynamic ratio, X: Blood Glucose). A lower value ==> less steep == less aggressive.\n\nThe autosens.min/max settings determines both the max/min limits for the dynamic ratio AND how much the dynamic ratio is adjusted. If AF is the slope of the curve, the autosens.min/max is the height of the graph, the Y-interval, where Y: dynamic ratio. The curve will always have a sigmoid shape, no matter which autosens.min/max settings are used, meaning these settings have big consequences for the outcome of the computed dynamic ISF. Please be careful setting a too high autosens.max value. With a proper profile ISF setting, you will probably never need it to be higher than 1.5\n\nAn Autosens.max limit > 1.5 is not advisable when using the sigmoid function.",
                                            useGraphics: nil
                                        )
                                    }
                            }.disabled(isPresented)
                        }
                    } header: { Text("Formula") }

                    Section {
                        HStack {
                            Text("Adjustment Factor")
                                .onTapGesture {
                                    info(
                                        header: "Adjustment Factor",
                                        body: "Individual adjustment of the computed dynamic ratios. Default is 0.5. The higher the value, the larger the correction of your ISF/CR will be for a high or a low blood glucose. Maximum/minumum correction is determined by the Autosens min/max settings.\n\nFor Sigmoid function an adjustment factor of 0.4 - 0.5 is recommended to begin with.\n\nFor the logaritmic formula there is less consensus, but starting around 0.8 is probably appropiate for most adult users. For younger users it's recommended to start even lower when using logaritmic formula, to avoid overly aggressive treatment.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.adjustmentFactor, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("Weighted Average of TDD. Weight of past 24 hours:")
                                .onTapGesture {
                                    info(
                                        header: "Weighted Average of TDD. Weight of past 24 hours:",
                                        body: "Has to be > 0 and <= 1.\nDefault is 0.65 (65 %) * TDD. The rest will be from average of total data (up to 14 days) of all TDD calculations (35 %). To only use past 24 hours, set this to 1.\n\nTo avoid sudden fluctuations, for instance after a big meal, an average of the past 2 hours of TDD calculations is used instead of just the current TDD (past 24 hours at this moment).",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.weightPercentage, formatter: formatter)
                                .disabled(isPresented)
                        }

                    } header: { Text("Settings") }
                }

                Section {
                    HStack {
                        Text("Threshold Setting")
                            .onTapGesture {
                                scrollView = true
                                graphics = thresholdTable().asAny()
                                let unitString = state.unit.rawValue
                                info(
                                    header: "Minimum Threshold Setting",
                                    body: NSLocalizedString(
                                        "This setting lets you choose a level below which no insulin will be given.\n\nThe threshold is using the largest amount of your threshold setting and the computed threshold:\n\nTarget Glucose - (Target Glucose - 40) / 2\n, here using mg/dl as glucose unit.\n\nFor example, if your Target Glucose is ",
                                        comment: "Threshold string part 1"
                                    ) + "\(glucoseString(100)) \(unitString) , " +
                                        NSLocalizedString("the threshold will be ", comment: "Threshold string part 2") +
                                        " \(glucoseString(70)) \(unitString), " + NSLocalizedString(
                                            "unless your threshold setting is set higher:",
                                            comment: "Threshold string part 3"
                                        ),
                                    useGraphics: graphics
                                )
                            }
                        Spacer()
                        DecimalTextField("0", value: $state.threshold_setting, formatter: glucoseFormatter)
                            .disabled(isPresented)
                        Text(state.unit.rawValue)
                    }
                } header: { Text("Safety") }

                if let averages = state.averages {
                    Section {
                        HStack {
                            Text("Average ISF")
                            Spacer()
                            Text(
                                glucoseFormatter
                                    .string(from: averages.isf as NSNumber) ?? ""
                            )
                            Text(state.unit.rawValue + NSLocalizedString("/U", comment: "")).foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Average CR")
                            Spacer()
                            Text(
                                daysFormatter
                                    .string(from: averages.cr as NSNumber) ?? ""
                            )
                            Text("g/U").foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Average CSF")
                            Spacer()
                            Text(
                                glucoseFormatter
                                    .string(from: (Double(averages.isf) / Double(averages.cr)) as NSNumber) ?? ""
                            )
                            Text(state.unit.rawValue + "/g").foregroundColor(.secondary)
                        }
                    } header: {
                        HStack(spacing: 0) {
                            Text("Averages")
                            Text(
                                " (" + (daysFormatter.string(from: averages.days as NSNumber) ?? "") + " " +
                                    NSLocalizedString("days", comment: " days of data") + ")"
                            )
                        }
                    }
                    footer: { Text("ISF: Insulin Sensitivity, CR: Carb Ratio,\nCSF: Carb Sensitivity = ISF/CR") }
                }
            }
            .blur(radius: isPresented ? 5 : 0)
            .description(isPresented: isPresented, alignment: .center) {
                if scrollView { infoScrollView() } else { infoView() }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationBarTitle("Dynamic ISF")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }

        func info(header: String, body: String, useGraphics: (any View)?) {
            isPresented.toggle()
            description = Text(NSLocalizedString(body, comment: "Dynamic ISF Setting"))
            descriptionHeader = Text(NSLocalizedString(header, comment: "Dynamic ISF Setting Title"))
            graphics = useGraphics
        }

        var info: some View {
            VStack(spacing: 20) {
                descriptionHeader.font(.title2).bold()
                description.font(.body)
            }
        }

        func infoView() -> some View {
            info
                .formatDescription()
                .onTapGesture {
                    isPresented.toggle()
                }
        }

        func infoScrollView() -> some View {
            ScrollView {
                VStack(spacing: 20) {
                    info
                    if let view = graphics {
                        view.asAny()
                    }
                }
            }
            .formatDescription()
            .onTapGesture {
                isPresented.toggle()
                scrollView = false
            }
        }

        func glucoseString(_ glucose: Int) -> String {
            glucoseFormatter.string(for: state.unit == .mgdL ? glucose : glucose.asMmolL as NSNumber) ?? ""
        }

        @ViewBuilder func thresholdTable() -> some View {
            let entries = [
                Thresholds(glucose: glucoseString(100), setting: glucoseString(65), threshold: glucoseString(70)),
                Thresholds(glucose: glucoseString(130), setting: glucoseString(65), threshold: glucoseString(85)),
                Thresholds(glucose: glucoseString(90), setting: glucoseString(65), threshold: glucoseString(65)),
                Thresholds(glucose: glucoseString(90), setting: glucoseString(80), threshold: glucoseString(80))
            ]

            Grid {
                GridRow {
                    Text("Glucose Target")
                    Text("Setting")
                    Text("Threshold")
                }
                .bold()
                Divider()
                ForEach(entries) { entry in
                    GridRow {
                        Text(entry.glucose)
                        Text(entry.setting)
                        Text(entry.threshold)
                    }
                    if entry != entries.last {
                        Divider()
                    }
                }
            }
            .padding(.all, 20)
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorScheme == .dark ? Color(.black) : Color(.white))
            )
        }
    }
}
