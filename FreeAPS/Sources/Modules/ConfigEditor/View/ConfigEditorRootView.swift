import SwiftUI

extension ConfigEditor {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>
        @State private var showShareSheet = false

        var body: some View {
            TextEditor(text: $viewModel.configText)
                .keyboardType(.asciiCapable)
                .font(.system(.subheadline, design: .monospaced))
                .allowsTightening(true)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        Button { showShareSheet = true }
                        label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .navigationBarItems(
                    trailing: Button("Save", action: viewModel.save)
                )
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(activityItems: [viewModel.provider.urlFor(file: viewModel.file)!])
                }
                .navigationTitle(viewModel.file)
                .navigationBarTitleDisplayMode(.inline)
                .padding()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    typealias Callback = (_ activityType: UIActivity.ActivityType?, _ completed: Bool, _ returnedItems: [Any]?, _ error: Error?)
        -> Void

    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    let excludedActivityTypes: [UIActivity.ActivityType]? = nil
    let callback: Callback? = nil

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = callback
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {
        // nothing to do here
    }
}
