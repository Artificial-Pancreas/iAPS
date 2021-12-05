import SwiftUI
import Swinject

extension AppleHealthKit {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Form {
                Section {
                    Toggle("Connect to Apple Health", isOn: $state.useAppleHealth)
                    if state.needShowInformationTextForSetPermissions {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text("For write data to Apple Health you must give permissions in Settings > Health > Data Access")
                                .font(.caption)
                        }
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
