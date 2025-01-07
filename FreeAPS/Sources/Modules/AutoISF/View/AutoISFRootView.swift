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

        @Environment(\.colorScheme) var colorScheme
        @Environment(\.sizeCategory) private var fontSize

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
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

                        HStack {
                            Toggle(isOn: $state.enableautoISFwithCOB) {
                                Text("Enable DuraISF effect even with COB")
                                    .onTapGesture {
                                        info(
                                            header: "Enable DuraISF effect even with COB",
                                            body: "Enable DuraISF even if COB is present not just for UAM.",
                                            useGraphics: nil
                                        )
                                    }
                            }.disabled(isPresented)
                        }

                        HStack {
                            Toggle(isOn: $state.postMealISFalways) {
                                Text("Enable postprandial ISF adaption always")
                                    .onTapGesture {
                                        info(
                                            header: "Enable postprandial ISF always",
                                            body: "Enable the postprandial ISF adaptation all the time regardless of when the last meal was taken.",
                                            useGraphics: nil
                                        )
                                    }
                            }.disabled(isPresented)
                        }
                    } header: { Text("Toggles") }

                    Section {
                        HStack {
                            Text("Auto ISF Max / Min settings:")
                                .navigationLink(to: .preferencesEditor, from: self)
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
                                        body: "Default value: 0, Sensible is bteween 40 and 120. The linearly increasing SMB delivery ratio is mapped to the glucose range [target_bg, target_bg+bg_range]. At target_bg the SMB ratio is smb_delivery_ratio_min, at target_bg+bg_range it is smb_delivery_ratio_max. With 0 the linearly increasing SMB ratio is disabled and the standard smb_delivery_ratio is used.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.smbDeliveryRatioBGrange, formatter: formatter)
                                .disabled(isPresented)
                            Text("mg/dl").foregroundStyle(.secondary)
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
                            Text("ISF weight for higher BG deltas")
                                .onTapGesture {
                                    info(
                                        header: "ISF weight for higher BG deltas",
                                        body: "Default value: 0.0 This is the weight applied to the polygon which adapts ISF higher deltas. With 0.0 the effect is effectively disabled.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.deltaISFrangeWeight, formatter: formatter)
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
                            Text("Duration ISF postprandial adaption")
                                .onTapGesture {
                                    info(
                                        header: "Duration ISF postprandial adaption",
                                        body: "Default value: 3. This is the duration in hours how long after a meal the effect will be active. Oref will delete carb timing after 10 hours latest no matter what you enter.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.postMealISFduration, formatter: formatter)
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
                            Text("Target Level in mg/dl for B30 to be enacted")
                                .onTapGesture {
                                    info(
                                        header: "Target Level in mg/dl for B30 to be enacted",
                                        body: "An EatingSoon Override Target (or a Temporary Target) needs to be activated to start the B30 adaption. Target needs to be below or equal this  setting for B30 AIMI to start. Default is 90 mg/dl. If you cancel this EatingSoon Target, the B30 basal rate will stop.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.b30targetLevel, formatter: formatter)
                                .disabled(isPresented)
                            Text("mg/dl").foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Upper BG limit in mg/dl for B30")
                                .onTapGesture {
                                    info(
                                        header: "Upper BG limit in mg/dl for B30",
                                        body: "B30 will only run as long as BG stays underneath that level, if above regular autoISF takes over. Default is 130 mg/dl.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.b30upperLimit, formatter: formatter)
                                .disabled(isPresented)
                            Text("mg/dl").foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Upper Delta limit in mg/dl for B30")
                                .onTapGesture {
                                    info(
                                        header: "Upper Delta limit in mg/dl for B30",
                                        body: "B30 will only run as long as BG delta stays below that level, if above regular autoISF takes over. Default is 8 mg/dl.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("0", value: $state.b30upperdelta, formatter: formatter)
                                .disabled(isPresented)
                            Text("mg/dl").foregroundStyle(.secondary)
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
        }

        func info(header: String, body: String, useGraphics: (any View)?) {
            isPresented.toggle()
            description = Text(NSLocalizedString(body, comment: "Auto ISF Setting"))
            descriptionHeader = Text(NSLocalizedString(header, comment: "Auto ISF Setting Title"))
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
            .frame(maxHeight: 500)
            .formatDescription()
            .onTapGesture {
                isPresented.toggle()
                scrollView = false
            }
        }

        var list: some View {
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
    }
}
