import LoopKit
import SwiftUI
import Swinject

extension AutoISF {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State var isPresented = false
        @State var description = Text("")
        @State var descriptionHeader = Text("")
        @State var scrollView = false
        @State var graphics: (any View)?
        @State var presentHistory = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(\.sizeCategory) private var fontSize

        @FetchRequest(
            entity: Reasons.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "date > %@", DateFilter().day)
        ) var reasons: FetchedResults<Reasons>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.decimalSeparator = "." // Homogenize as the ratios are always formatted using "."
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.decimalSeparator = "."
            if state.settingsManager.settings.units == .mmolL {
                formatter.maximumFractionDigits = 1
                formatter.minimumFractionDigits = 1
            } else {
                formatter.maximumFractionDigits = 0
            }
            return formatter
        }

        private var reqFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.decimalSeparator = "."
            formatter.minimumFractionDigits = 2
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "sv")
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    HStack {
                        Toggle(isOn: $state.autoisf) {
                            Text("Enable Auto ISF")
                                .onTapGesture {
                                    info(
                                        header: "Enable Auto ISF",
                                        body: "Enables Auto ISF. This will disable any eventual dynamic ISF/CR setting",
                                        useGraphics: nil
                                    )
                                }
                        }.disabled(isPresented)
                    }
                } header: { Text("Experimental").foregroundStyle(.red) }

                if state.autoisf {
                    Section {
                        HStack {
                            Toggle(isOn: $state.enableBGacceleration) {
                                Text("Enable BG acceleration")
                                    .onTapGesture {
                                        info(
                                            header: "Enable BG acceleration",
                                            body: "Enables the BG acceleration adaptions, adjusting ISF for accelerating/decelerating blood glucose.",
                                            useGraphics: nil
                                        )
                                    }
                            }.disabled(isPresented)
                        }
                    } header: { Text("Toggles") }

                    Section {
                        HStack {
                            Text("Auto ISF Max")
                                .onTapGesture {
                                    info(
                                        header: "Auto ISF Max",
                                        body: "Default value: 1.2 The upper limit of ISF adjustment",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.autoisf_max, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("Auto ISF Min")
                                .onTapGesture {
                                    info(
                                        header: "Auto ISF Min",
                                        body: "Default value: 0.8 The lower limit of ISF adjustment",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.autoisf_min, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("SMB Delivery Ratio Minimum")
                                .onTapGesture {
                                    info(
                                        header: "SMB Delivery Ratio Minimum",
                                        body: "Default value: 0.5 This is the lower end of a linearly increasing SMB Delivery Ratio rather than the fix value in OpenAP SMB Delivery Ratio.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.smbDeliveryRatioMin, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("SMB DeliveryRatio Maximum")
                                .onTapGesture {
                                    info(
                                        header: "SMB Delivery Ratio Maximum",
                                        body: "Default value: 0.5 This is the higher end of a linearly increasing SMB Delivery Ratio rather than the fix value in OpenAP SMB Delivery Ratio.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.smbDeliveryRatioMax, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("SMB Delivery Ratio BG Range")
                                .onTapGesture {
                                    info(
                                        header: "SMB Delivery Ratio BG Range",
                                        body: "Default value: 0, Sensible is between 40 mg/dL and 120 mg/dL. The linearly increasing SMB delivery ratio is mapped to the glucose range [target_bg, target_bg+bg_range]. At target_bg the SMB ratio is smb_delivery_ratio_min, at target_bg+bg_range it is smb_delivery_ratio_max. With 0 the linearly increasing SMB ratio is disabled and the standard smb_delivery_ratio is used.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            BGTextField(
                                "0",
                                mgdlValue: $state.smbDeliveryRatioBGrange,
                                units: $state.units,
                                isDisabled: isPresented
                            )
                        }

                        HStack {
                            Text("Auto ISF Hourly Max Change")
                                .onTapGesture {
                                    info(
                                        header: "Auto ISF Hourly Max Change",
                                        body: "Rate at which ISF is reduced per hour assuming BG leveel remains at double target for that time. When value = 1.0, ISF is reduced to 50% after 1 hour of BG level at 2x target.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.autoISFhourlyChange, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("ISF weight for higher BG's")
                                .onTapGesture {
                                    info(
                                        header: "ISF weight for higher BG's",
                                        body: "Default value: 0.0 This is the weight applied to the polygon which adapts ISF if glucose is above target. With 0.0 the effect is effectively disabled.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.higherISFrangeWeight, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("ISF weight for lower BG's")
                                .onTapGesture {
                                    info(
                                        header: "ISF weight for lower BG's",
                                        body: "Default value: 0.0 This is the weight applied to the polygon which adapts ISF if glucose is below target. With 0.0 the effect is effectively disabled.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.lowerISFrangeWeight, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("ISF weight for postprandial BG rise")
                                .onTapGesture {
                                    info(
                                        header: "ISF weight for postprandial BG rise",
                                        body: "This is the weight applied to the linear slope while glucose rises and  which adapts ISF. With 0 this contribution is effectively disabled. Start with 0.01 - it hardly goes beyond 0.05!",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.postMealISFweight, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("ISF weight while BG accelerates")
                                .onTapGesture {
                                    info(
                                        header: "ISF weight while BG accelerates",
                                        body: "Default value: 0. This is the weight applied while glucose accelerates and which strengthens ISF. With 0 this contribution is effectively disabled. 0.02 is a safe starting point, from which to move up. Typical settings are around 0.15!",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.bgAccelISFweight, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("ISF weight while BG decelerates")
                                .onTapGesture {
                                    info(
                                        header: "ISF weight while BG decelerates",
                                        body: "This is the weight applied while glucose decelerates and which weakens ISF. With 0 this contribution is effectively disabled. 0.1 might be a good starting point.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.bgBrakeISFweight, formatter: formatter)
                                .disabled(isPresented)
                        }

                        HStack {
                            Text("Max IOB Threshold Percent")
                                .onTapGesture {
                                    info(
                                        header: "Max IOB Threshold Percent",
                                        body: "Percent of the max IOB setting to use for SMBs while Auto ISF is enabled.\n\nWhile current IOB is below the threshold, the SMB amount can exceed the threshold by 30%, however never the max IOB setting.\n\nAt 100% this setting is disabled.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.iobThresholdPercent, formatter: formatter)
                                .disabled(isPresented)
                        }
                    } header: { Text("Settings") }

                    Section {
                        HStack {
                            Toggle(isOn: $state.use_B30) {
                                Text("Activate AIMI B30")
                                    .onTapGesture {
                                        scrollView = true
                                        graphics = list.asAny()
                                        info(
                                            header: "Activate AIMI B30",
                                            body: "Enables an increased basal rate after an EatingSoon Override Target (or Temp Target) and a manual bolus to saturate the infusion site with insulin to increase insulin absorption for SMB's following a meal with no carb counting.",
                                            useGraphics: list
                                        )
                                    }
                            }.disabled(isPresented)
                        }

                        if state.use_B30 {
                            HStack {
                                Text("Minimum Start Bolus size")
                                    .onTapGesture {
                                        info(
                                            header: "Minimum Start Bolus size",
                                            body: "Minimum manual bolus to start a B30 adaption.",
                                            useGraphics: nil
                                        )
                                    }
                                Spacer()
                                DecimalTextField("0", value: $state.iTime_Start_Bolus, formatter: formatter)
                                    .disabled(isPresented)
                            }

                            HStack {
                                Text("Target Level for B30 to be enacted")
                                    .onTapGesture {
                                        info(
                                            header: "Target Level for B30 to be enacted",
                                            body: "An EatingSoon Override Target (or a Temporary Target) needs to be activated to start the B30 adaption. Target needs to be below or equal this  setting for B30 AIMI to start. Default is 90 mg/dl. If you cancel this EatingSoon Target, the B30 basal rate will stop.",
                                            useGraphics: nil
                                        )
                                    }
                                Spacer()
                                BGTextField(
                                    "0",
                                    mgdlValue: $state.b30targetLevel,
                                    units: $state.units,
                                    isDisabled: isPresented
                                )
                            }

                            HStack {
                                Text("Upper BG limit")
                                    .onTapGesture {
                                        info(
                                            header: "Upper BG limit",
                                            body: "SMBs will be diabled when under this limit, while a B30 Basal rate is running. Default is 130 mg/dl (7.2 mmol/l).",
                                            useGraphics: nil
                                        )
                                    }
                                Spacer()
                                BGTextField(
                                    "0",
                                    mgdlValue: $state.b30upperLimit,
                                    units: $state.units,
                                    isDisabled: isPresented
                                )
                            }

                            HStack {
                                Text("Upper Delta limit")
                                    .onTapGesture {
                                        info(
                                            header: "Upper Delta limit",
                                            body: "SMBs will be diabled when under this limit, while a B30 Basal rate is running. Default is 8 mg/dl (0.5 mmol/l).",
                                            useGraphics: nil
                                        )
                                    }
                                Spacer()
                                BGTextField(
                                    "0",
                                    mgdlValue: $state.b30upperdelta,
                                    units: $state.units,
                                    isDisabled: isPresented
                                )
                            }

                            HStack {
                                Text("B30 Basal rate increase factor")
                                    .onTapGesture {
                                        info(
                                            header: "B30 Basal rate increase factor",
                                            body: "Factor that multiplies your normal regular basal rate for B30. Max Basal rate enacted is the max of your pump max Basal setting. Default is 5.",
                                            useGraphics: nil
                                        )
                                    }
                                Spacer()
                                DecimalTextField("0", value: $state.b30factor, formatter: formatter)
                                    .disabled(isPresented)
                            }

                            HStack {
                                Text("Duration of increased B30 basal rate")
                                    .onTapGesture {
                                        info(
                                            header: "Duration of increased B30 basal rate",
                                            body: "Duration of increased basal rate that saturates the infusion site with insulin. Default 30 minutes, as in B30. The EatingSoon TT needs to be running at least for this duration, otherthise B30 will stopp after the TT runs out.",
                                            useGraphics: nil
                                        )
                                    }
                                Spacer()
                                DecimalTextField("0", value: $state.b30_duration, formatter: formatter)
                                    .disabled(isPresented)
                            }
                        }
                    } header: { Text("AIMI B30 Settings") }

                    Section {
                        HStack {
                            Toggle(isOn: $state.ketoProtect) {
                                Text("Enable Keto Protection")
                                    .onTapGesture {
                                        info(
                                            header: "Enable Keto Protection",
                                            body: "Ketoacidosis protection will apply a small configurable Temp Basal Rate always or if certain conditions arise instead of a Zero temp!\nThe feature exists because in special cases a person could get ketoacidosis from 0% TBR. The idea is derived from sport. There could be problems when a basal rate of 0% ran for several hours. Muscles in particular could shut off.\nThis feature enables a small safety TBR to reduce the ketoacidosis risk. Without the Variable Protection that safety TBR is always applied. The idea behind the variable protection strategy is that the safety TBR is only applied if sum of basal-IOB and bolus-IOB falls negatively below the value of the current basal rate.",
                                            useGraphics: nil
                                        )
                                    }
                            }.disabled(isPresented)
                        }

                        if state.ketoProtect {
                            HStack {
                                Toggle(isOn: $state.variableKetoProtect) {
                                    Text("Variable Keto Protection")
                                        .onTapGesture {
                                            info(
                                                header: "Variable Keto Protection",
                                                body: "If activated the small safety TBR kicks in when IOB is in negative range as if no basal insulin has been delivered for one hour. If deactivated and static is enabled every Zero Temp is replaced with the small TBR.",
                                                useGraphics: nil
                                            )
                                        }
                                }.disabled(isPresented)
                            }
                            if state.variableKetoProtect {
                                HStack {
                                    Text("Safety TBR in %")
                                        .onTapGesture {
                                            info(
                                                header: "Safety TBR in %",
                                                body: "Quantity of the small safety TBR in % of Profile BR, which is given to avoid ketoacidosis. Will be limited to min = 5%, max = 50%!",
                                                useGraphics: nil
                                            )
                                        }
                                    Spacer()
                                    DecimalTextField("0", value: $state.ketoProtectBasalPercent, formatter: formatter)
                                        .disabled(isPresented)
                                }
                            }

                            HStack {
                                Toggle(isOn: $state.ketoProtectAbsolut) {
                                    Text("Enable Keto protection with pre-defined TBR")
                                        .onTapGesture {
                                            info(
                                                header: "Enable Keto protection with pre-defined TBR",
                                                body: "Should an absolute TBR between 0 and 2 U/hr be specified instead of percentage of current BR",
                                                useGraphics: nil
                                            )
                                        }
                                }.disabled(isPresented)
                            }

                            if state.ketoProtectAbsolut {
                                HStack {
                                    Text("Absolute Safety TBR ")
                                        .onTapGesture {
                                            info(
                                                header: "Absolute Safety TBR ",
                                                body: "Amount in U/hr of the small safety TBR, which is given to avoid ketoacidosis. Will be limited to min = 0U/hr, max = 2U/hr!",
                                                useGraphics: nil
                                            )
                                        }
                                    Spacer()
                                    DecimalTextField("0", value: $state.ketoProtectBasalAbsolut, formatter: formatter)
                                        .disabled(isPresented)
                                }
                            }
                        }
                    } header: { Text("Keto Protection") }

                    Section {
                        HStack {
                            Text("History")
                            Spacer()
                            Text(">").foregroundStyle(.secondary)
                        }.onTapGesture { presentHistory.toggle() }
                    } header: { Text("History") }
                }
            }
            .blur(radius: isPresented ? 5 : 0)
            .description(isPresented: isPresented, alignment: .center) {
                if scrollView { infoScrollView() } else { infoView() }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationBarTitle("Auto ISF")
            .navigationBarTitleDisplayMode(.automatic)

            .sheet(isPresented: $presentHistory) {
                history
            }
        }

        private func info(header: String, body: String, useGraphics: (any View)?) {
            isPresented.toggle()
            description = Text(LocalizedStringKey(body))
            descriptionHeader = Text(NSLocalizedString(header, comment: "Auto ISF Setting Title"))
            graphics = useGraphics
        }

        private var info: some View {
            VStack(spacing: 20) {
                descriptionHeader.font(.title2).bold()
                description.font(.body)
            }
        }

        private func infoView() -> some View {
            info
                .formatDescription()
                .onTapGesture {
                    isPresented.toggle()
                }
        }

        private func infoScrollView() -> some View {
            ScrollView {
                VStack(spacing: 20) {
                    info
                    if let view = graphics {
                        view.asAny()
                    }
                }
            }
            .frame(maxHeight: 500)
            .formatDescription()
            .onTapGesture {
                isPresented.toggle()
                scrollView = false
            }
        }

        private var list: some View {
            let entries = [
                Table(
                    localizedString: "Needs an EatingSoon specific Glucose Target set by a profile override or a temp target"
                ),
                Table(
                    localizedString: "Once this Target is cancelled, the B30 high TBR will be cancelled"
                ),
                Table(
                    localizedString: "In order to activate B30 a minimum manual Bolus needs to be given"
                ),
                Table(
                    localizedString: "You can specify how long B30 run and how high it is"
                )
            ]

            return Grid {
                ForEach(entries) { entry in
                    GridRow {
                        Text(entry.point).frame(maxHeight: .infinity, alignment: .top)
                        Text(entry.localizedString).frame(maxWidth: .infinity, alignment: .leading)
                    }.listRowSpacing(10)
                }
            }

            .padding(.all, 20)
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorScheme == .dark ? Color(.black).opacity(0.3) : Color(.white))
            )
        }

        private var history: some View {
            VStack(spacing: 0) {
                Button { presentHistory.toggle() }
                label: { Image(systemName: "chevron.backward") }.tint(.blue).opacity(0.8).buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 22))
                    .padding(10)
                // Title
                Text("Auto ISF History")
                    .padding(.bottom, 20)
                    .font(.system(size: 26))

                // SubTitle
                HStack {
                    Text("Final Ratio").foregroundStyle(.red)
                    Spacer()
                    Text("Adjustments").foregroundStyle(.orange).offset(x: -20)
                    Spacer()
                    Text("Insulin").foregroundStyle(Color(.insulin))
                }
                .font(.system(size: 18))
                .padding(.bottom, 5)
                .padding(.horizontal, 20)

                Divider()

                // SubTitle
                // Non-localized variable acronyms
                HStack(spacing: 10) {
                    Text("Time").foregroundStyle(.primary)
                    Text("BG  ").foregroundStyle(Color(.loopGreen))
                    Text("Final").foregroundStyle(.red)
                    Spacer(minLength: 3)
                    Text("acce").foregroundStyle(.orange).offset(x: -3)
                    Text("bg  ").foregroundStyle(.orange)
                    Text("dura  ").foregroundStyle(.orange)
                    Text("pp  ").foregroundStyle(.orange)
                    Spacer(minLength: 3)
                    Text("Req. ").foregroundColor(.secondary)
                    Text("TBR ").foregroundColor(.blue)
                    Text("SMB ").foregroundColor(.blue)
                }
                .padding(.horizontal, 5)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)

                Divider()

                List {
                    // Non-localized data table
                    ForEach(reasons) { item in
                        if let glucose = item.glucose, glucose != 0, let aisf_reaons = item.reasons {
                            // Prepare an array of Strings
                            let reasonParsed = aisf_reaons.string.components(separatedBy: ",")
                                .filter({ $0 != "AIMI B30 active" }).map(
                                    { item in
                                        let check = item.components(separatedBy: ":").last ?? ""
                                        return check == " 1" ? " -- " : check
                                    }
                                )
                            let converted = state.units == .mmolL ? (glucose as Decimal)
                                .asMmolL : (glucose as Decimal)
                            Grid(horizontalSpacing: 0) {
                                GridRow {
                                    // Time
                                    Text(dateFormatter.string(from: item.date ?? Date()))
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .offset(x: 7)
                                    Spacer(minLength: 5)
                                    // Glucose
                                    Text(glucoseFormatter.string(from: converted as NSNumber) ?? "")
                                        .foregroundStyle(Color(.loopGreen))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .offset(x: 4)
                                    // Ratio
                                    Text((formatter.string(from: item.ratio ?? 1) ?? "") + "  ").foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    if reasonParsed.count >= 4 {
                                        // acce.
                                        Text((reasonParsed.first ?? "") + "  ")
                                            .foregroundStyle(.orange)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .offset(x: 5)
                                        // bg
                                        Text(reasonParsed[1] + "  ")
                                            .foregroundStyle(.orange)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .offset(x: 8)
                                        // dura
                                        Text(reasonParsed[2] + "  ")
                                            .foregroundStyle(.orange)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .offset(x: 5)
                                        // pp
                                        Text(reasonParsed[3] + "  ")
                                            .foregroundStyle(.orange)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .offset(x: 3)
                                    }
                                    Spacer(minLength: 13)
                                    // Insunlin Required
                                    let insReqString = reqFormatter.string(from: (item.insulinReq ?? 0) as NSNumber) ?? ""
                                    Text(insReqString != "0.00" ? insReqString + " " : "0  ")
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Spacer(minLength: 2)
                                    // Basal Rate
                                    Text((formatter.string(from: (item.rate ?? 0) as NSNumber) ?? "") + " ")
                                        .foregroundColor(Color(.insulin))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    // SMBs
                                    Text(
                                        (item.smb ?? 0) != 0 ?
                                            "\(formatter.string(from: (item.smb ?? 0) as NSNumber) ?? "")  "
                                            : "   "
                                    )
                                    .foregroundColor(Color(.insulin))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .listRowBackground(colorScheme == .dark ? Color(.black) : Color(.white))
                }
                .font(.system(size: 12))
                .listStyle(.plain)
            }
        }
    }
}
