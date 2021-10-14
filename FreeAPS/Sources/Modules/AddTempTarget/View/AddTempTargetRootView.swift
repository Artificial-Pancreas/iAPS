import SwiftUI

extension AddTempTarget {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>
        @State private var isPromtPresented = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                if !viewModel.presets.isEmpty {
                    Section(header: Text("Presets")) {
                        ForEach(viewModel.presets) { preset in
                            presetView(for: preset)
                        }
                    }
                }

                Section(header: Text("Custom")) {
                    HStack {
                        Text("Bottom target")
                        Spacer()
                        DecimalTextField("0", value: $viewModel.low, formatter: formatter, cleanInput: true)
                        Text(viewModel.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Top target")
                        Spacer()
                        DecimalTextField("0", value: $viewModel.high, formatter: formatter, cleanInput: true)
                        Text(viewModel.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        DecimalTextField("0", value: $viewModel.duration, formatter: formatter, cleanInput: true)
                        Text("minutes").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $viewModel.date)
                    Button { isPromtPresented = true }
                    label: { Text("Save as preset") }
                }

                Section {
                    Button { viewModel.enact() }
                    label: { Text("Enact") }
                    Button { viewModel.cancel() }
                    label: { Text("Cancel Temp Target") }
                }
            }
            .popover(isPresented: $isPromtPresented) {
                Form {
                    Section(header: Text("Enter preset name")) {
                        TextField("Name", text: $viewModel.newPresetName)
                        Button {
                            viewModel.save()
                            isPromtPresented = false
                        }
                        label: { Text("Save") }
                        Button { isPromtPresented = false }
                        label: { Text("Cancel") }
                    }
                }
            }
            .navigationTitle("Enact Temp Target")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }

        private func presetView(for preset: TempTarget) -> some View {
            var low = preset.targetBottom
            var high = preset.targetTop
            if viewModel.units == .mmolL {
                low = low?.asMmolL
                high = high?.asMmolL
            }
            return HStack {
                VStack {
                    HStack {
                        Text(preset.displayName)
                        Spacer()
                    }
                    HStack {
                        Text(
                            "\(formatter.string(from: (low ?? 0) as NSNumber)!) - \(formatter.string(from: (high ?? 0) as NSNumber)!)"
                        )
                        .foregroundColor(.secondary)
                        .font(.caption)

                        Text(viewModel.units.rawValue)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("for \(formatter.string(from: preset.duration as NSNumber)!) min")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Spacer()
                    }.padding(.top, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.enactPreset(id: preset.id)
                }

                Image(systemName: "xmark.circle").foregroundColor(.secondary)
                    .contentShape(Rectangle())
                    .padding(.vertical)
                    .onTapGesture {
                        removeAlert = Alert(
                            title: Text("Are you sure?"),
                            message: Text("Delete preset \"\(preset.displayName)\""),
                            primaryButton: .destructive(Text("Delete"), action: { viewModel.removePreset(id: preset.id) }),
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
