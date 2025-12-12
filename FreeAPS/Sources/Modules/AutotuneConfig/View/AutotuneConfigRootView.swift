import SwiftUI
import Swinject

extension AutotuneConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel
        @State var replaceAlert = false

        private var isfFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            return formatter
        }

        private func roundToNearestBasalStep(_ value: Decimal) -> Decimal {
            let step = Decimal(0.05)
            let scaled = (value / step)
            let roundedDouble = (scaled as NSDecimalNumber).doubleValue.rounded()
            let rounded = roundedDouble * 0.05
            return Decimal(rounded)
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }

        private let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()

        private let outputTimeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter
        }()

        private func matchingProfileEntry(forSuggestedIndex index: Int) -> BasalProfileEntry? {
            guard let autotune = state.autotune else { return nil }

            let suggested = autotune.basalProfile[index]
            let suggestedEnds: Int =
                (index + 1 < autotune.basalProfile.count)
                    ? autotune.basalProfile[index + 1].minutes
                    : 24 * 60

            return state.currentProfile.enumerated().first(where: { currentIndex, currentEntry in
                let nextOffset =
                    (currentIndex + 1 < state.currentProfile.count)
                        ? state.currentProfile[currentIndex + 1].minutes
                        : 24 * 60

                return currentEntry.minutes <= suggested.minutes && suggestedEnds <= nextOffset
            })?.element
        }

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            Form {
                autotuneToggles
                runSection
                runningIndicator

                if let autotune = state.autotune, !state.running {
                    if !state.onlyAutotuneBasals {
                        carbAndSensitivitySection(autotune)
                    }

                    basalProfileSection(autotune)
                    deleteSection
                    saveSection
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Autotune")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(Text("Are you sure?"), isPresented: $replaceAlert) {
                Button("Yes") {
                    state.replace()
                    replaceAlert.toggle()
                }
                Button("No") {
                    replaceAlert.toggle()
                }
            }
        }

        private var autotuneToggles: some View {
            Section {
                Toggle("Use Autotune", isOn: $state.useAutotune)
                if state.useAutotune {
                    Toggle("Only Autotune Basal Insulin", isOn: $state.onlyAutotuneBasals)
                }
            }
        }

        private var runSection: some View {
            Section {
                HStack {
                    Text("Last run")
                    Spacer()
                    Text(dateFormatter.string(from: state.publishedDate))
                }
                Button("Run now") {
                    state.run()
                }
            }
        }

        private var runningIndicator: some View {
            Section {
                if state.running {
                    HStack {
                        Text("Wait please").foregroundColor(.secondary)
                        Spacer()
                        ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    }
                }
            }
        }

        private func carbAndSensitivitySection(_ autotune: Autotune) -> some View {
            Section {
                HStack {
                    Text("Carb ratio")
                    Spacer()
                    Text(isfFormatter.string(from: autotune.carbRatio as NSNumber) ?? "0")
                    Text("g/U").foregroundColor(.secondary)
                }
                HStack {
                    Text("Sensitivity")
                    Spacer()
                    if state.units == .mmolL {
                        Text(isfFormatter.string(from: autotune.sensitivity.asMmolL as NSNumber) ?? "0")
                    } else {
                        Text(isfFormatter.string(from: autotune.sensitivity as NSNumber) ?? "0")
                    }
                    Text(state.units.rawValue + "/U").foregroundColor(.secondary)
                }
            }
        }

        @ViewBuilder private func basalProfileSection(_ autotune: Autotune) -> some View {
            Section(header: Text("Basal profile")) {
                Grid {
                    ForEach(0 ..< autotune.basalProfile.count, id: \.self) { index in
                        basalProfileRow(for: autotune, index: index)
                        Divider()
                    }

                    GridRow {
                        Text("Total")
                            .bold()
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(rateFormatter.string(from: state.currentTotal as NSNumber) ?? "0")
                            .foregroundColor(.secondary)
                        Text("⇢").foregroundColor(.secondary)

                        let total = autotune.basalProfile.reduce(Decimal(0)) { $0 + $1.rate }
                        let roundedTotal = roundToNearestBasalStep(total)

                        Text(rateFormatter.string(from: roundedTotal as NSNumber) ?? "0")
                            .foregroundColor(.primary)

                        Text("U/day").foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }

        @ViewBuilder private func basalProfileRow(for autotune: Autotune, index: Int) -> some View {
            GridRow {
                if let date = timeFormatter.date(from: autotune.basalProfile[index].start) {
                    Text(outputTimeFormatter.string(from: date))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(autotune.basalProfile[index].start)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let current = matchingProfileEntry(forSuggestedIndex: index) {
                    let oldRate = roundToNearestBasalStep(current.rate)
                    let newRate = roundToNearestBasalStep(autotune.basalProfile[index].rate)
                    let difference = newRate - oldRate
                    let tolerance = Decimal(0.0001)

                    if abs(difference) > tolerance {
                        Text(rateFormatter.string(from: oldRate as NSNumber) ?? "0")
                            .foregroundColor(.secondary)

                        Text("⇢").foregroundColor(.secondary)

                        Text(rateFormatter.string(from: newRate as NSNumber) ?? "0")
                            .foregroundColor(.primary)
                    } else {
                        Text("")
                        Text("")
                        Text(rateFormatter.string(from: newRate as NSNumber) ?? "0")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("")
                    Text("")
                    Text(rateFormatter.string(from: autotune.basalProfile[index].rate as NSNumber) ?? "0")
                        .foregroundColor(.secondary)
                }

                Text("U/hr").foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }

        private var deleteSection: some View {
            Section {
                Button(role: .destructive) {
                    state.delete()
                } label: {
                    Text("Delete autotune data")
                }
            }
        }

        private var saveSection: some View {
            Section(header: Text("Save on Pump")) {
                Button("Save as your Normal Basal Rates") {
                    replaceAlert = true
                }
            }
        }
    }
}
