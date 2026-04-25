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
