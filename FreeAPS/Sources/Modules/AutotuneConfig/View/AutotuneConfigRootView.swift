import SwiftUI
import Swinject

extension AutotuneConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }

        private var scaleFormatter: NumberFormatter {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
            return f
        }

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            Form {
                togglesSection
                runSection
                runningIndicator
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Autotune")
            .navigationBarTitleDisplayMode(.automatic)
        }

        // MARK: - Sections

        @ViewBuilder
        private var togglesSection: some View {
            Section {
                Toggle("Use Autotune", isOn: $state.useAutotune)

                if state.useAutotune {
                    Toggle("Only Autotune Basal Insulin", isOn: $state.onlyAutotuneBasals)
                    Toggle("Calculate ISF Suggestions", isOn: $state.calculateISFSuggestions)

                    NavigationLink(destination: CalculatedBasalView(state: state)) {
                        subPageRow(
                            label: "Calculated Basal",
                            subtitle: state.autotune != nil
                                ? dateFormatter.string(from: state.publishedDate)
                                : "No data yet"
                        )
                    }

                    if state.calculateISFSuggestions {
                        HStack {
                            Text("ISF Scale")
                                .onTapGesture {
                                    info(
                                        header: "ISF Scale",
                                        body: "Multiplier applied to the calculated ISF schedule when saving to your profile. Default is 1.0 (no change). Reduce below 1.0 (e.g. 0.93) if the algorithm consistently needs more insulin than the calculated ISF provides — this shifts the entire 24-hour schedule proportionally. Increase above 1.0 to make the profile more conservative. Change in small steps (0.02–0.05) and allow 2–3 days to evaluate.",
                                        useGraphics: nil
                                    )
                                }
                            Spacer()
                            DecimalTextField("1.00", value: $state.isfScale, formatter: scaleFormatter)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                        }

                        NavigationLink(destination: CalculatedISFView(state: state)) {
                            subPageRow(
                                label: "Calculated ISF",
                                subtitle: state.isfSchedule.map { dateFormatter.string(from: $0.generatedAt) }
                                    ?? "No data yet"
                            )
                        }
                    }
                }
            }
        }

        private var runSection: some View {
            Section {
                HStack {
                    Text("Last run")
                    Spacer()
                    Text(dateFormatter.string(from: state.publishedDate))
                        .foregroundColor(.secondary)
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

        // MARK: - Helpers

        private func subPageRow(label: String, subtitle: String) -> some View {
            HStack {
                Text(label)
                Spacer()
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}
