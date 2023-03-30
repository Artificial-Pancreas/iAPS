import CoreData
import SwiftUI
import Swinject

extension AddTempTarget {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var isPromtPresented = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?
        @State private var isEditing = false

        @FetchRequest(
            entity: ViewPercentage.entity(),
            sortDescriptors: [NSSortDescriptor(key: "enabled", ascending: false)]
        ) var isEnabledArray: FetchedResults<ViewPercentage>

        @Environment(\.managedObjectContext) var moc

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                if !state.presets.isEmpty {
                    Section(header: Text("Presets")) {
                        ForEach(state.presets) { preset in
                            presetView(for: preset)
                        }
                    }
                }
                HStack {
                    Text("Advanced")
                    Toggle(isOn: $state.viewPercentage) {}.controlSize(.mini)
                    Image(systemName: "figure.highintensity.intervaltraining")
                    Image(systemName: "fork.knife")
                }

                if state.viewPercentage {
                    Section(
                        header: Text("TT Effect on Insulin")
                    ) {
                        VStack {
                            HStack {
                                Text(NSLocalizedString("Target", comment: ""))
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.low,
                                    formatter: formatter,
                                    cleanInput: true
                                )
                                Text(state.units.rawValue).foregroundColor(.secondary)
                            }

                            if computeSliderLow() != computeSliderHigh() {
                                Text(NSLocalizedString("Percent Insulin", comment: ""))
                                Slider(
                                    value: $state.percentage,
                                    in: computeSliderLow() ... computeSliderHigh(),
                                    step: 5
                                ) {}
                                minimumValueLabel: { Text("\(computeSliderLow(), specifier: "%.0f")%") }
                                maximumValueLabel: { Text("\(computeSliderHigh(), specifier: "%.0f")%") }
                                onEditingChanged: { editing in
                                    isEditing = editing }

                                Text("\(state.percentage.formatted(.number)) %")
                                    .foregroundColor(isEditing ? .orange : .blue)
                                    .font(.largeTitle)
                                Divider()
                                Text(
                                    state
                                        .units == .mgdL ? "Half normal Basal at: \(computeHBT().formatted(.number)) mg/dl" :
                                        "Half normal Basal at: \(computeHBT().asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L"
                                )
                                .foregroundColor(.secondary)
                                .font(.caption).italic()
//                                Divider()
//                                if state.percentage != 100 && state.percentage != round(Double(computeRatio())) {
//                                    Text(
//                                        "Enter HBT in Preferences to achieve Insulin Ratio." + "\n" +
//                                            "If you don't, the set Target will put you at Insulin Ratio of " +
//                                            "\(computeRatio().formatted(.number)) % as HBT is currently \(state.halfBasal) mg/dL."
//                                    )
//                                    .foregroundColor(.loopRed)
//                                    .fixedSize(horizontal: false, vertical: true)
//                                    .multilineTextAlignment(.leading).font(.caption)
//                                }
                            } else {
                                Text(
                                    "You have not enabled the proper Preferences to change sensitivity with chosen TempTarget. Verify Autosens Max, lowTT lowers Sens and highTT raises Sens (or Exercise Mode)!"
                                )
                                // .foregroundColor(.loopRed)
                                .font(.caption).italic()
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            }
                        }
                    }
                } else {
                    Section(header: Text("Custom")) {
                        HStack {
                            Text("Target")
                            Spacer()
                            DecimalTextField("0", value: $state.low, formatter: formatter, cleanInput: true)
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Duration")
                            Spacer()
                            DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromtPresented = true }
                        label: { Text("Save as preset") }
                    }
                }
                if state.viewPercentage {
                    Section {
                        HStack {
                            Text("Duration")
                            Spacer()
                            DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromtPresented = true }
                        label: { Text("Save as preset") }
                    }
                }

                Section {
                    Button { state.enact() }
                    label: { Text("Enact") }
                    Button { state.cancel() }
                    label: { Text("Cancel Temp Target") }
                }
            }
            .popover(isPresented: $isPromtPresented) {
                Form {
                    Section(header: Text("Enter preset name")) {
                        TextField("Name", text: $state.newPresetName)
                        Button {
                            state.save()
                            isPromtPresented = false
                        }
                        label: { Text("Save") }
                        Button { isPromtPresented = false }
                        label: { Text("Cancel") }
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Enact Temp Target")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
            .onDisappear {
                if state.viewPercentage {
                    let isEnabledMoc = ViewPercentage(context: moc)
                    isEnabledMoc.enabled = true
                    isEnabledMoc.date = Date()
                    try? moc.save()
                } else {
                    let isEnabledMoc = ViewPercentage(context: moc)
                    isEnabledMoc.enabled = false
                    isEnabledMoc.date = Date()
                    try? moc.save()
                }
            }
        }

        func computeTarget() -> Decimal {
            var ratio = Decimal(state.percentage / 100)
            let hB = state.halfBasal
            let c = hB - 100
            var target = (c / ratio) - c + 100
            if c * (c + target - 100) <= 0 {
                ratio = state.maxValue
                target = (c / ratio) - c + 100
            }
            return target
        }

        func computeRatio() -> Decimal {
            let hbt = state.halfBasal
            let normalTarget: Decimal = 100
            var target: Decimal = state.low
            if state.units == .mmolL { target = Decimal(round(Double(target.asMgdL))) }
            var ratio: Decimal = 1
            if (target + hbt - (2 * normalTarget)) !=
                0.0 { ratio = (hbt - normalTarget) / (target + hbt - (2 * normalTarget)) } // prevent division by 0
            if ratio < 0 { ratio = state.maxValue } // if negative Value take max Ratio
            ratio = Decimal(round(Double(min(ratio, state.maxValue) * 100)))
            return ratio
        }

        func computeHBT() -> Decimal {
            let ratio = Decimal(state.percentage / 100)
            let normalTarget: Decimal = 100
            var target: Decimal = state.low
            if state.units == .mmolL { target = Decimal(round(Double(target.asMgdL))) }
            var hbt: Decimal = state.halfBasal
            if ratio != 1 {
                hbt = ((2 * ratio * normalTarget) - normalTarget - (ratio * target)) / (ratio - 1)
            }
            hbt = Decimal(round(Double(hbt)))
            // state.halfBasal = hbt
            return hbt
        }

        func computeSliderLow() -> Double {
            var minSens: Double = 15
            var target = state.low
            if state.units == .mmolL {
                target = Decimal(round(Double(state.low.asMgdL))) }
            if target == 0 { return minSens }
            if target < 100 || (!state.highTTraises && !state.exerMode) { minSens = 100 }
            // minSens = min(minSens, 95)
            return minSens
        }

        func computeSliderHigh() -> Double {
            var maxSens = Double(state.maxValue * 100)
            var target = state.low
            if target == 0 { return maxSens }
            if state.units == .mmolL {
                target = state.low / 0.0555 }
            if target > 100 || !state.lowTTlowers { maxSens = 100 }
            // maxSens = max(105, maxSens)
            return maxSens
        }

        private func presetView(for preset: TempTarget) -> some View {
            var low = preset.targetBottom
            var high = preset.targetTop
            if state.units == .mmolL {
                low = low?.asMmolL
                high = high?.asMmolL
            }
            return HStack {
                VStack {
                    HStack {
                        Text(preset.displayName)
                        Spacer()
                    }
                    HStack(spacing: 2) {
                        Text(
                            "\(formatter.string(from: (low ?? 0) as NSNumber)!) - \(formatter.string(from: (high ?? 0) as NSNumber)!)"
                        )
                        .foregroundColor(.secondary)
                        .font(.caption)

                        Text(state.units.rawValue)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("for")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("\(formatter.string(from: preset.duration as NSNumber)!)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("min")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Spacer()
                    }.padding(.top, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    state.enactPreset(id: preset.id)
                }

                Image(systemName: "xmark.circle").foregroundColor(.secondary)
                    .contentShape(Rectangle())
                    .padding(.vertical)
                    .onTapGesture {
                        removeAlert = Alert(
                            title: Text("Are you sure?"),
                            message: Text("Delete preset \"\(preset.displayName)\""),
                            primaryButton: .destructive(Text("Delete"), action: { state.removePreset(id: preset.id) }),
                            secondaryButton: .cancel()
                        )
                        isRemoveAlertPresented = true
                    }
                    .alert(isPresented: $isRemoveAlertPresented) {
                        removeAlert!
                    }
            }
        }
    }
}
