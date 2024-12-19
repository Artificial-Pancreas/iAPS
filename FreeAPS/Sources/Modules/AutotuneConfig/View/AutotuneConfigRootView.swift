import SwiftUI
import Swinject

extension AutotuneConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
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
            guard let autotune = state.autotune else {
                return nil
            }

            let suggested = autotune.basalProfile[index]
            let suggestedEnds: Int
            if index + 1 < autotune.basalProfile.count {
                suggestedEnds = autotune.basalProfile[index + 1].minutes
            } else {
                suggestedEnds = 24 * 60 // End of day in minutes
            }

            return state.currentProfile.enumerated().first(where: { currentIndex, currentEntry in
                let nextOffset: Int
                if currentIndex + 1 < state.currentProfile.count {
                    nextOffset = state.currentProfile[currentIndex + 1].minutes
                } else {
                    nextOffset = 24 * 60 // End of day in minutes
                }

                return currentEntry.minutes <= suggested.minutes && suggestedEnds <= nextOffset
            })?.element
        }

        var body: some View {
            Form {
                Section {
                    Toggle("Use Autotune", isOn: $state.useAutotune)
                    if state.useAutotune {
                        Toggle("Only Autotune Basal Insulin", isOn: $state.onlyAutotuneBasals)
                    }
                }

                Section {
                    HStack {
                        Text("Last run")
                        Spacer()
                        Text(dateFormatter.string(from: state.publishedDate))
                    }
                    Button { state.run() }
                    label: { Text("Run now") }
                }

                if let autotune = state.autotune {
                    if !state.onlyAutotuneBasals {
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

                    Section(header: Text("Basal profile")) {
                        Grid {
                            ForEach(0 ..< autotune.basalProfile.count, id: \.self) { index in
                                GridRow {
                                    if let date = timeFormatter.date(from: autotune.basalProfile[index].start) {
                                        Text(outputTimeFormatter.string(from: date)).foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text(autotune.basalProfile[index].start).foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    if let current = matchingProfileEntry(forSuggestedIndex: index) {
                                        Text(rateFormatter.string(from: current.rate as NSNumber) ?? "0")
                                            .foregroundColor(.secondary)
                                        Text("⇢").foregroundColor(.secondary)
                                    } else {
                                        Text("") // Empty cells if no match
                                        Text("")
                                    }

                                    Text(rateFormatter.string(from: autotune.basalProfile[index].rate as NSNumber) ?? "0")
                                    Text("U/hr").foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)

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

                                Text(
                                    rateFormatter
                                        .string(from: autotune.basalProfile.reduce(0) { $0 + $1.rate } as NSNumber) ?? "0"
                                )
                                .foregroundColor(.primary)

                                Text("U/day").foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    Section {
                        Button { state.delete() }
                        label: { Text("Delete autotune data") }
                            .foregroundColor(.red)
                    }

                    Section {
                        Button {
                            replaceAlert = true
                        }
                        label: { Text("Save as your Normal Basal Rates") }
                    } header: {
                        Text("Save on Pump")
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle("Autotune")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(Text("Are you sure?"), isPresented: $replaceAlert) {
                Button("Yes", action: {
                    state.replace()
                    replaceAlert.toggle()
                })
                Button("No", action: { replaceAlert.toggle() })
            }
        }
    }
}
