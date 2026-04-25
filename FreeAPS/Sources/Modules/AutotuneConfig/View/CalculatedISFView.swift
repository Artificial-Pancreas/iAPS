import SwiftUI

extension AutotuneConfig {
    struct CalculatedISFView: View {
        @ObservedObject var state: StateModel
        @State private var saveAlert = false

        private var dateFormatter: DateFormatter {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }

        private var shortDateFormatter: DateFormatter {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f
        }

        private let hourFormatter: DateFormatter = {
            let f = DateFormatter()
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "HH:mm"
            return f
        }()

        private func hourLabel(_ hour: Int) -> String {
            let date = Date(timeIntervalSince1970: TimeInterval(hour * 3600))
            return hourFormatter.string(from: date)
        }

        private var isfUnit: String {
            state.units.rawValue + "/U"
        }

        var body: some View {
            Form {
                if let schedule = state.isfSchedule {
                    metadataSection(schedule)
                    scheduleSection(schedule)
                    saveSection
                } else {
                    noDataSection
                }
            }
            .navigationTitle("Calculated ISF")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(Text("Save to Profile ISF?"), isPresented: $saveAlert) {
                Button("Save") {
                    state.saveISFToProfile()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will replace your current ISF schedule with 24 hourly values " +
                    "calculated from your last \(state.isfSchedule?.daysAnalyzed ?? 0) days of loop data. " +
                    "Your previous schedule will be overwritten."
                )
            }
        }

        // MARK: - Sections

        private func metadataSection(_ schedule: ReasonsISFSchedule) -> some View {
            Section(header: Text("Data Summary")) {
                HStack {
                    Text("Last calculated")
                    Spacer()
                    Text(dateFormatter.string(from: schedule.generatedAt))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Days of data")
                    Spacer()
                    Text("\(schedule.daysAnalyzed) days")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Date range")
                    Spacer()
                    Text("\(shortDateFormatter.string(from: schedule.fromDate)) – \(shortDateFormatter.string(from: schedule.toDate))")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
                HStack {
                    Text("Loop entries used")
                    Spacer()
                    Text("\(schedule.qualifyingEntries) of \(schedule.totalEntries)")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Overall median ISF")
                    Spacer()
                    let median = state.displayISF(mgdl: schedule.overallMedian)
                    Text("\(median) \(isfUnit)")
                        .foregroundColor(.secondary)
                }
                if let suggestedMedian = schedule.overallSuggestedMedian {
                    HStack {
                        Text("Suggested median ISF")
                        Spacer()
                        let suggested = state.displayISF(mgdl: suggestedMedian)
                        Text("\(suggested) \(isfUnit)")
                            .foregroundColor(.accentColor)
                            .fontWeight(.semibold)
                    }
                }
                HStack {
                    Text("Deviation entries")
                    Spacer()
                    Text("\(schedule.devQualifyingEntries ?? 0)")
                        .foregroundColor(.secondary)
                }

                infoNote
            }
        }

        private var infoNote: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("How this is calculated")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(
                    "Calculated — Each loop cycle records the applied ISF and the sensitivity ratio. " +
                    "The profile ISF is back-calculated as ISF × ratio across the past 21 days, " +
                    "the top and bottom 5% are trimmed, and per-hour medians are computed. " +
                    "Hours with fewer than 3 data points are interpolated from the nearest measured hour."
                )
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 2)
                Text(
                    "Adjusted — A second pass compares how much BG actually moved against what the " +
                    "back-calculated ISF predicted. If BG consistently drops more than expected at a given hour, " +
                    "the ISF suggestion is raised; if it drops less, it is lowered. " +
                    "The adjustment is capped at ±20% per run to prevent overcorrection. " +
                    "A large gap between Calculated and Adjusted means the actual glucose response at that hour " +
                    "differs meaningfully from what the profile predicts — for example, the end of dawn phenomenon " +
                    "around 04–06 h often shows insulin becoming noticeably more effective."
                )
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 2)
            }
            .padding(.vertical, 4)
        }

        private func scheduleSection(_ schedule: ReasonsISFSchedule) -> some View {
            Section(header: scheduleHeader) {
                ForEach(0 ..< 24, id: \.self) { hour in
                    scheduleRow(hour: hour, schedule: schedule)
                }
            }
        }

        private var scheduleHeader: some View {
            Grid {
                GridRow {
                    Text("Time")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Current")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Calculated")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Adjusted")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("n")
                        .frame(width: 30, alignment: .trailing)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }

        @ViewBuilder
        private func scheduleRow(hour: Int, schedule: ReasonsISFSchedule) -> some View {
            let count = schedule.counts[String(hour)] ?? 0
            let isInterpolated = count < 3
            let calculatedMgdl = schedule.hours[String(hour)]
            let calculated = calculatedMgdl.map { state.displayISF(mgdl: $0) }
            let suggestedMgdl = schedule.suggestedHours?[String(hour)]
            let adjusted = (suggestedMgdl ?? calculatedMgdl).map { roundedISF(mgdl: $0) }
            let hasDeviation = suggestedMgdl != nil && !isInterpolated
            let current = state.currentISFForHour(hour)

            Grid {
                GridRow {
                    Text(hourLabel(hour))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let c = current {
                        Text("\(c)")
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if let calc = calculated {
                        Text("\(calc)")
                            .foregroundColor(isInterpolated ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if let r = adjusted {
                        Text("\(r)")
                            .foregroundColor(isInterpolated ? .secondary : hasDeviation ? .accentColor : .primary)
                            .fontWeight(hasDeviation ? .semibold : isInterpolated ? .regular : .regular)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    Text(isInterpolated ? "~" : "\(count)")
                        .foregroundColor(isInterpolated ? .secondary : .primary)
                        .font(.footnote)
                        .frame(width: 30, alignment: .trailing)
                }
            }
            .opacity(isInterpolated ? 0.6 : 1.0)
        }

        private var saveSection: some View {
            Section {
                Button(action: { saveAlert = true }) {
                    HStack {
                        Spacer()
                        Text("Save to Profile ISF")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .foregroundColor(.accentColor)

                Text("Applying this schedule will overwrite your current ISF profile with 24 hourly entries. Review the values above before saving.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }

        private var noDataSection: some View {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No data yet")
                        .fontWeight(.semibold)
                    Text(
                        "Run Autotune to calculate your ISF schedule. " +
                        "The calculation requires at least 12 hours of your day to have 3 or more loop data points each, " +
                        "drawn from the past 21 days."
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }

        // MARK: - Helpers

        /// Rounds an ISF to the nearest display-unit increment (0.1 mmol/L or 1 mg/dL).
        private func roundedISF(mgdl: Double) -> Decimal {
            if state.units == .mmolL {
                let mmol = mgdl * Double(GlucoseUnits.exchangeRate)
                return Decimal((mmol * 10).rounded() / 10)
            } else {
                return Decimal(Int(mgdl.rounded()))
            }
        }
    }
}
