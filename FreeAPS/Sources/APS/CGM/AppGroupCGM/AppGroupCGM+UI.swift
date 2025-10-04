import Combine
import Foundation
import HealthKit
import LibreTransmitter
import LoopKit
import LoopKitUI
import Swinject

extension AppGroupCGM: CGMManagerUI {
    public static var onboardingImage: UIImage? {
        nil
    }

    public static func setupViewController(
        bluetoothProvider _: LoopKit.BluetoothProvider,
        displayGlucosePreference _: DisplayGlucosePreference,
        colorPalette _: LoopKitUI.LoopUIColorPalette,
        allowDebugFeatures _: Bool,
        prefersToSkipUserInteraction _: Bool
    ) -> LoopKitUI.SetupUIResult<LoopKitUI.CGMManagerViewController, LoopKitUI.CGMManagerUI>
    {
        .createdAndOnboarded(AppGroupCGM())
    }

    public func settingsViewController(
        bluetoothProvider _: BluetoothProvider,
        displayGlucosePreference: DisplayGlucosePreference,
        colorPalette _: LoopUIColorPalette,
        allowDebugFeatures _: Bool
    ) -> CGMManagerViewController
    {
        let settings = AppGroupCGMSettingsViewController(cgmManager: self, displayGlucosePreference: displayGlucosePreference)
        let nav = CGMManagerSettingsNavigationViewController(rootViewController: settings)
        return nav
    }

    public var smallImage: UIImage? {
        nil
    }

    public var cgmStatusHighlight: DeviceStatusHighlight? {
        if let appName = appGroupSource.latestReadingFrom?.displayName ?? appGroupSource.latestReadingFromOther {
            return AppGroupCGMStatusHighlight(
                localizedMessage: NSLocalizedString("Reading from \(appName)", comment: "App Group CGM reading from ... status"),
                imageName: "dot.radiowaves.left.and.right",
                state: .normalCGM
            )
        }
        return AppGroupCGMStatusHighlight(
            localizedMessage: NSLocalizedString("No readings", comment: "App Group CGM not reading status"),
            imageName: "exclamationmark.circle.fill",
            state: .warning
        )
    }

    public var cgmStatusBadge: DeviceStatusBadge? {
        nil
    }

    public var cgmLifecycleProgress: DeviceLifecycleProgress? {
        nil
    }
}

struct AppGroupCGMStatusHighlight: DeviceStatusHighlight {
    let localizedMessage: String
    let imageName: String
    let state: DeviceStatusHighlightState
}
