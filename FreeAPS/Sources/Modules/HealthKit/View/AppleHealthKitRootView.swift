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
                } footer: {
                    if state.useAppleHealth, state.needShowInformationTextForSetPermissions {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(
                                "To allow iAPS to write data to Apple Health, you must grant permission in Settings > Health > Data Access."
                            )
                        }
                        .foregroundColor(Color.warning)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "info.circle")
                            Text(
                                "This allows iAPS to read from and write to Apple Heath. You must also give permissions in Settings > Health > Data Access."
                            )
                        }
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
