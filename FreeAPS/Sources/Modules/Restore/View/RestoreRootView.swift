import SwiftUI
import Swinject

extension Restore {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var openAPS: Preferences?

        @Environment(\.dismiss) private var dismiss

        var fetchedVersionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        var GlucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                importResetSettingsView
            }
            .onAppear(perform: configureView)
            .navigationTitle("Restore OpenAPS Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
        }

        private var importResetSettingsView: some View {
            Section {
                HStack {
                    Button {
                        importOpenAPSOnly()
                    }
                    label: { Text("Yes") }
                        .buttonStyle(.borderless)
                        .padding(.leading, 10)

                    Spacer()

                    Button {
                        dismiss()
                    }
                    label: { Text("No") }
                        .buttonStyle(.borderless)
                        .tint(.red)
                        .padding(.trailing, 10)
                }
            } header: {
                VStack {
                    Text("Welcome to iAPS, v\(fetchedVersionNumber)!")
                        .font(.previewHeadline).frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 40)

                    Text(
                        "In this new version the OpenAPS settings have been reset to default settings, due to a resolved Type error.\n\nFortunately you have a retrieved backup of your old OpenAPS settings in the cloud (open-iaps.app).\n\nIf you want to use these fetched settings tap \"Yes\""
                    )
                    .font(.previewNormal)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .textCase(nil)
                .foregroundStyle(.primary)
            }
        }

        private func importOpenAPSOnly() {
            if let preferences = openAPS {
                state.saveFile(preferences, filename: OpenAPS.Settings.preferences)
                debug(.service, "Imported OpenAPS Settings have been saved to file storage.")
            }
        }
    }
}
