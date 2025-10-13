
import Combine
import SwiftUI

final class AppGroupCGMSettingsViewModel: ObservableObject {
    let appGroupSource: AppGroupSource
    @Published var latestReadingFrom: AppGroupSourceType? = nil
    @Published var latestReadingFromOther: String? = nil
    @Published var latestReadingDate: Date? = nil
    @Published var deviceAddress: String? = nil

    let onDelete = PassthroughSubject<Void, Never>()
    let onClose = PassthroughSubject<Void, Never>()

    init(appGroupSource: AppGroupSource) {
        self.appGroupSource = appGroupSource
    }

    func viewDidAppear() {
        updateServiceStatus()
    }

    private func updateServiceStatus() {
        latestReadingDate = appGroupSource.latestReadingDate
        latestReadingFrom = appGroupSource.latestReadingFrom
        latestReadingFromOther = appGroupSource.latestReadingFromOther
        deviceAddress = appGroupSource.deviceAddress
    }
}

public struct AppGroupCGMSettingsView: View {
    @ObservedObject var viewModel: AppGroupCGMSettingsViewModel
    @State private var showingDeletionSheet = false

    init(viewModel: AppGroupCGMSettingsViewModel) {
        self.viewModel = viewModel
    }

    private var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()

        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("E, MMM d, hh:mm")

        return formatter
    }()

    public var body: some View {
        VStack {
            Spacer()
            Text(NSLocalizedString("Shared App Group CGM", comment: "Title for the Shared App Group CGM settings view"))
                .font(.title)
                .fontWeight(.semibold)
            Form {
                Section {
                    HStack {
                        Text("Reading from:")
                        Spacer()
                        Text(viewModel.latestReadingFrom?.displayName ?? viewModel.latestReadingFromOther ?? "--")
                    }
                    HStack {
                        Text("Latest reading:")
                        Spacer()
                        if let latestReadingDate = viewModel.latestReadingDate {
                            Text(timeFormatter.string(from: latestReadingDate))
                        } else {
                            Text("--")
                        }
                    }
                }
                Section(header: Text("Heartbeat")) {
                    VStack(alignment: .leading) {
                        if let cgmTransmitterDeviceAddress = viewModel.deviceAddress {
                            Text("CGM address :")
                            Text(cgmTransmitterDeviceAddress).font(.caption)
                        } else {
                            Text("CGM is not used as heartbeat.")
                        }
                    }
                }
                if let latestReadingFrom = viewModel.latestReadingFrom, let appURL = latestReadingFrom.appURL {
                    Section {
                        Button(
                            NSLocalizedString("Open \(latestReadingFrom.displayName)", comment: "Open the shared group app"),
                            action: {
                                UIApplication.shared.open(appURL)
                            }
                        )
                    }
                }
                Section {
                    HStack {
                        Spacer()
                        deleteCGMButton
                        Spacer()
                    }
                }
            }
        }
        .navigationBarItems(
            trailing: Button(action: {
                self.viewModel.onClose.send()
            }, label: {
                Text("Done")
            })
        ).onAppear {
            viewModel.viewDidAppear()
        }
    }

    private var deleteCGMButton: some View {
        Button(action: {
            showingDeletionSheet = true
        }, label: {
            Text("Delete CGM").foregroundColor(.red)
        }).actionSheet(isPresented: $showingDeletionSheet) {
            ActionSheet(
                title: Text("Are you sure you want to delete this CGM?"),
                buttons: [
                    .destructive(Text("Delete CGM")) {
                        self.viewModel.onDelete.send()
                    },
                    .cancel()
                ]
            )
        }
    }
}
