import SwiftUI
import Swinject

extension BolusCalculatorConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State var isPresented = false
        @State var description = Text("")
        @State var descriptionHeader = Text("")
        @State var confirm = false
        @State var graphics: (any View)?

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

        var body: some View {
            Form {
                Section {
                    HStack {
                        Toggle("Use alternate Bolus Calculator", isOn: $state.useCalc)
                    }

                    if state.useCalc {
                        HStack {
                            Text("Override With A Factor Of ")
                            Spacer()
                            DecimalTextField("0.8", value: $state.overrideFactor, formatter: conversionFormatter)
                        }
                    }

                    if !state.useCalc {
                        HStack {
                            Text("Recommended Bolus Percentage")
                            DecimalTextField("", value: $state.insulinReqPercentage, formatter: formatter)
                        }
                    }
                } header: { Text("Calculator settings") }

                Section {
                    Toggle("Display Predictions", isOn: $state.displayPredictions)

                } header: { Text("Smaller iPhone Screens") }

                if state.useCalc {
                    Section {
                        HStack {
                            Toggle("Apply factor for fatty meals", isOn: $state.fattyMeals)
                        }
                        HStack {
                            Text("Override With A Factor Of ")
                            Spacer()
                            DecimalTextField("0.7", value: $state.fattyMealFactor, formatter: conversionFormatter)
                        }
                    } header: { Text("Fatty Meals") }

                    Section {}
                    footer: { Text(
                        "The new alternate bolus calculator is another approach to the default bolus calculator in iAPS. If the toggle is on you use this bolus calculator and not the original iAPS calculator. At the end of the calculation a custom factor is applied as it is supposed to be when using smbs (default 0.8).\n\nYou can also add the option in your bolus calculator to apply another (!) customizable factor at the end of the calculation which could be useful for fatty meals, e.g Pizza (default 0.7)."
                    )
                    }
                }
                Section {
                    HStack {
                        Toggle(isOn: $state.allowBolusShortcut) {
                            Text("Allow iOS Bolus Shortcuts").foregroundStyle(state.allowBolusShortcut ? .red : .primary)
                        }.disabled(isPresented)
                            ._onBindingChange($state.allowBolusShortcut, perform: { _ in
                                if state.allowBolusShortcut {
                                    confirm = true
                                    graphics = confirmButton()
                                    info(
                                        header: "Allow iOS Bolus Shortcuts",
                                        body: "If you enable this setting you will be able to use iOS shortcuts and its automations to trigger a bolus in iAPS.\n\nObserve that the iOS shortuts also works with Siri!\n\nIf you need to use Bolus Shorcuts, please make sure to turn off the listen for 'Hey Siri' setting in iPhone Siri settings, to avoid any inadvertant activaton of a bolus with Siri.\nIf you don't disable 'Hey Siri' the iAPS bolus shortcut can be triggered with the utterance 'Hey Siri, iAPS Bolus'.\n\nWhen triggered with Siri you will be asked for an amount and a confirmation before the bolus command can be sent to iAPS.",
                                        useGraphics: graphics
                                    )
                                }
                            })
                    }
                    if state.allowBolusShortcut {
                        HStack {
                            Text(
                                state.allowedRemoteBolusAmount > state.settingsManager.pumpSettings
                                    .maxBolus ? "Max Bolus exceeded!" :
                                    "Max allowed bolus amount using shortcuts "
                            )
                            .foregroundStyle(
                                state.allowedRemoteBolusAmount > state.settingsManager.pumpSettings
                                    .maxBolus ? .red : .primary
                            )
                            Spacer()
                            DecimalTextField("0", value: $state.allowedRemoteBolusAmount, formatter: conversionFormatter)
                        }
                    }
                } header: { Text("Allow iOS Bolus Shortcuts") }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationBarTitle("Bolus Calculator")
            .navigationBarTitleDisplayMode(.automatic)
            .blur(radius: isPresented ? 5 : 0)
            .description(isPresented: isPresented, alignment: .center) {
                if confirm { confirmationView() } else { infoView() }
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
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }

        func infoView() -> some View {
            info
                .formatDescription()
                .onTapGesture {
                    isPresented.toggle()
                }
        }

        func confirmationView() -> some View {
            ScrollView {
                VStack(spacing: 20) {
                    info
                    if let view = graphics {
                        view.asAny()
                    }
                }
                .formatDescription()
            }
        }

        @ViewBuilder func confirmButton() -> some View {
            HStack(spacing: 20) {
                Button("Enable") {
                    state.allowBolusShortcut = true
                    isPresented.toggle()
                    confirm = false
                }.buttonStyle(.borderedProminent).tint(.blue)

                Button("Cancel") {
                    state.allowBolusShortcut = false
                    isPresented.toggle()
                    confirm = false
                }.buttonStyle(.borderedProminent).tint(.red)
            }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }
}
