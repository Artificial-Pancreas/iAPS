import SwiftUI

extension AutotuneConfig {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        private var isfFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 3
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    Toggle("Use Autotune", isOn: $viewModel.useAutotune)
                }

                Section {
                    HStack {
                        Text("Last run")
                        Spacer()
                        Text(dateFormatter.string(from: viewModel.publishedDate))
                    }
                    Button { viewModel.run() }
                    label: { Text("Run now") }
                }

                if let autotune = viewModel.autotune {
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
                            if viewModel.units == .mmolL {
                                Text(isfFormatter.string(from: autotune.sensitivity.asMmolL as NSNumber) ?? "0")
                            } else {
                                Text(isfFormatter.string(from: autotune.sensitivity as NSNumber) ?? "0")
                            }
                            Text(viewModel.units.rawValue + "/U").foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("Basal profile")) {
                        ForEach(0 ..< autotune.basalProfile.count, id: \.self) { index in
                            HStack {
                                Text(autotune.basalProfile[index].start).foregroundColor(.secondary)
                                Spacer()
                                Text(rateFormatter.string(from: autotune.basalProfile[index].rate as NSNumber) ?? "0")
                                Text("U/hr").foregroundColor(.secondary)
                            }
                        }
                    }

                    Section {
                        Button { viewModel.delete() }
                        label: { Text("Delete autotune data") }
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Autotune")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
