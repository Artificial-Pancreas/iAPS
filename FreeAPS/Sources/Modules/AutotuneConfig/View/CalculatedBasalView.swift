import SwiftUI

extension AutotuneConfig {
    struct CalculatedBasalView: View {
        @ObservedObject var state: StateModel
        @State private var replaceAlert = false

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

        private let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f
        }()

        private let outputTimeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f
        }()

        private func roundToNearestBasalStep(_ value: Decimal) -> Decimal {
            let step = Decimal(state.increment)
            let scaled = value / step
            let roundedDouble = (scaled as NSDecimalNumber).doubleValue.rounded()
            return Decimal(roundedDouble * state.increment)
        }

        private func matchingProfileEntry(forSuggestedIndex index: Int) -> BasalProfileEntry? {
            guard let autotune = state.autotune else { return nil }
            let suggested = autotune.basalProfile[index]
            let suggestedEnds = (index + 1 < autotune.basalProfile.count)
                ? autotune.basalProfile[index + 1].minutes
                : 24 * 60
            return state.currentProfile.enumerated().first(where: { currentIndex, currentEntry in
                let nextOffset = (currentIndex + 1 < state.currentProfile.count)
                    ? state.currentProfile[currentIndex + 1].minutes
                    : 24 * 60
                return currentEntry.minutes <= suggested.minutes && suggestedEnds <= nextOffset
            })?.element
        }

        var body: some View {
            Form {
                if let autotune = state.autotune {
                    if !state.onlyAutotuneBasals {
                        carbAndSensitivitySection(autotune)
                    }
                    basalProfileSection(autotune)
                    deleteSection
                    saveSection
                } else {
                    noDataSection
                }
            }
            .navigationTitle("Calculated Basal")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(Text("Are you sure?"), isPresented: $replaceAlert) {
                Button("Yes") {
                    state.replace()
                    replaceAlert = false
                }
                Button("No") {
                    replaceAlert = false
                }
            }
        }

        // MARK: - Sections

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

        private var noDataSection: some View {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No data yet")
                        .fontWeight(.semibold)
                    Text("Run Autotune from the previous screen to generate basal suggestions.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
