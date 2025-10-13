import Combine
import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI

public final class AppGroupCGMSettingsViewController: UIHostingController<AppGroupCGMSettingsView>, CompletionNotifying {
    public var completionDelegate: CompletionDelegate?

    public let cgmManager: AppGroupCGM

    public let displayGlucosePreference: DisplayGlucosePreference

    private var viewModel: AppGroupCGMSettingsViewModel

    private var lifetime: AnyCancellable?

    public init(cgmManager: AppGroupCGM, displayGlucosePreference: DisplayGlucosePreference) {
        self.cgmManager = cgmManager
        self.displayGlucosePreference = displayGlucosePreference
        viewModel = AppGroupCGMSettingsViewModel(appGroupSource: cgmManager.appGroupSource)
        let view = AppGroupCGMSettingsView(viewModel: viewModel)
        super.init(rootView: view)

        subscribeOnChanges()
    }

    private func subscribeOnChanges() {
        let onClose = viewModel.onClose
            .sink { [weak self] in
                guard let self = self else { return }
                self.completionDelegate?.completionNotifyingDidComplete(self)
                self.dismiss(animated: true)
            }

        let onDelete = viewModel.onDelete
            .sink { [weak self] in
                guard let self = self else { return }
                self.cgmManager.notifyDelegateOfDeletion {
                    DispatchQueue.main.async {
                        self.completionDelegate?.completionNotifyingDidComplete(self)
                        self.dismiss(animated: true)
                    }
                }
            }

        lifetime = AnyCancellable {
            onClose.cancel()
            onDelete.cancel()
        }
    }

    @available(*, unavailable)
    @objc dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
