import LoopKit
import LoopKitUI
import SwiftUI

extension MedtrumPumpManager: PumpManagerUI {
    public static func setupViewController(
        initialSettings settings: LoopKitUI.PumpManagerSetupSettings,
        bluetoothProvider _: any LoopKit.BluetoothProvider,
        colorPalette: LoopKitUI.LoopUIColorPalette,
        allowDebugFeatures: Bool,
        prefersToSkipUserInteraction _: Bool,
        allowedInsulinTypes: [LoopKit.InsulinType]
    ) -> LoopKitUI.SetupUIResult<any LoopKitUI.PumpManagerViewController, any LoopKitUI.PumpManagerUI> {
        let vc = MedtrumKitUICoordinator(
            colorPalette: colorPalette,
            pumpManagerSettings: settings,
            allowDebugFeatures: allowDebugFeatures,
            allowedInsulinTypes: allowedInsulinTypes
        )

        return .userInteractionRequired(vc)
    }

    // NOTE: iAPS support
    public static func setupViewController(
        initialSettings settings: LoopKitUI.PumpManagerSetupSettings,
        bluetoothProvider _: LoopKit.BluetoothProvider,
        colorPalette: LoopKitUI.LoopUIColorPalette,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [LoopKit.InsulinType]
    ) -> LoopKitUI.SetupUIResult<LoopKitUI.PumpManagerViewController, LoopKitUI.PumpManagerUI> {
        let vc = MedtrumKitUICoordinator(
            colorPalette: colorPalette,
            pumpManagerSettings: settings,
            allowDebugFeatures: allowDebugFeatures,
            allowedInsulinTypes: allowedInsulinTypes
        )

        return .userInteractionRequired(vc)
    }

    public func settingsViewController(
        bluetoothProvider _: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [InsulinType]
    ) -> PumpManagerViewController {
        MedtrumKitUICoordinator(
            pumpManager: self,
            colorPalette: colorPalette,
            allowDebugFeatures: allowDebugFeatures,
            allowedInsulinTypes: allowedInsulinTypes
        )
    }

    public func deliveryUncertaintyRecoveryViewController(
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool
    ) -> (UIViewController & CompletionNotifying) {
        return MedtrumKitUICoordinator(pumpManager: self, colorPalette: colorPalette, allowDebugFeatures: allowDebugFeatures)
    }

    public func hudProvider(
        bluetoothProvider: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowedInsulinTypes: [InsulinType]
    ) -> HUDProvider? {
        MedtrumKitHUDProvider(
            pumpManager: self,
            bluetoothProvider: bluetoothProvider,
            colorPalette: colorPalette,
            allowedInsulinTypes: allowedInsulinTypes
        )
    }

    public static func createHUDView(rawValue: [String: Any]) -> BaseHUDView? {
        MedtrumKitHUDProvider.createHUDView(rawValue: rawValue)
    }

    public static var onboardingImage: UIImage? {
        UIImage(named: "nano200", in: Bundle(for: MedtrumKitHUDProvider.self), compatibleWith: nil)
    }

    public var smallImage: UIImage? {
        UIImage(
            named: state.pumpName.contains("300u") ? "nano300" : "nano200",
            in: Bundle(for: MedtrumKitHUDProvider.self),
            compatibleWith: nil
        )
    }

    public var pumpStatusHighlight: DeviceStatusHighlight? {
        if state.reservoir < 1 {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString("No Insulin", comment: "Status highlight that a pump is out of insulin."),
                imageName: "exclamationmark.circle.fill",
                state: .critical
            )
        } else if state.basalState == .suspended {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString(
                    "Insulin Suspended",
                    comment: "Status highlight that insulin delivery was suspended."
                ),
                imageName: "pause.circle.fill",
                state: .warning
            )
        } else if Date.now.timeIntervalSince(state.lastSync) > .minutes(12) {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString(
                    "Signal Loss",
                    comment: "Status highlight when communications with the patch haven't happened recently."
                ),
                imageName: "exclamationmark.circle.fill",
                state: .critical
            )
        }

        return nil
    }

    // Not needed
    public var pumpLifecycleProgress: DeviceLifecycleProgress? {
        nil
    }

    // LoopKit only requires here to show "time sync required"
    // But this is handled during connection and can be left empty
    public var pumpStatusBadge: DeviceStatusBadge? {
        nil
    }
}
