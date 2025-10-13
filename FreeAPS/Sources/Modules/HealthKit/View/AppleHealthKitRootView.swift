import SwiftUI
import Swinject

extension AppleHealthKit {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            Form {
                Section {
                    Toggle("Connect to Apple Health", isOn: $state.useAppleHealth)
                    HStack {
                        Image(systemName: "pencil.circle.fill")
                        Text(
                            "This allows iAPS to read from and write to Apple Heath. You must also give permissions in Settings > Health > Data Access."
                        )
                        .font(.caption)
                    }
                    .foregroundColor(Color.secondary)
                    if state.needShowInformationTextForSetPermissions {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(
                                "To allow iAPS to write data to Apple Health, you must grant permission in Settings > Health > Data Access."
                            )
                            .font(.caption)
                        }
                        .foregroundColor(Color.secondary)
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
