import SwiftUI

extension Settings {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
//            Form {
//                Text("Open Editor").modal(for: .configEditor, from: self)
//                Text("Nightscout").modal(for: .nighscoutConfig, from: self)
//            }
            GlucoseRangeView()
                .toolbar { ToolbarItem(placement: .principal) { Text("Settings") } }
        }
    }
}
