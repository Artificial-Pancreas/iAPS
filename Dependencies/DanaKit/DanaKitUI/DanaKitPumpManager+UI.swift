//
//  DanaPumpManager+UI.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 18/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

extension DanaKitPumpManager : PumpManagerUI {
    public static func setupViewController(initialSettings settings: LoopKitUI.PumpManagerSetupSettings, bluetoothProvider: LoopKit.BluetoothProvider, colorPalette: LoopKitUI.LoopUIColorPalette, allowDebugFeatures: Bool, allowedInsulinTypes: [LoopKit.InsulinType]) -> LoopKitUI.SetupUIResult<LoopKitUI.PumpManagerViewController, LoopKitUI.PumpManagerUI> {
        let vc = DanaUICoordinator(colorPalette: colorPalette, pumpManagerSettings: settings, allowDebugFeatures: allowDebugFeatures, allowedInsulinTypes: allowedInsulinTypes)
        return .userInteractionRequired(vc)
    }
    
    public func settingsViewController(bluetoothProvider: BluetoothProvider, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, allowedInsulinTypes: [InsulinType]) -> PumpManagerViewController {
        return DanaUICoordinator(pumpManager: self, colorPalette: colorPalette, allowDebugFeatures: allowDebugFeatures, allowedInsulinTypes: allowedInsulinTypes)
    }
    
    public func deliveryUncertaintyRecoveryViewController(colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> (UIViewController & CompletionNotifying) {
        return DanaUICoordinator(pumpManager: self, colorPalette: colorPalette, allowDebugFeatures: allowDebugFeatures)
    }
    
    public func hudProvider(bluetoothProvider: BluetoothProvider, colorPalette: LoopUIColorPalette, allowedInsulinTypes: [InsulinType]) -> HUDProvider? {
        return DanaKitHUDProvider(pumpManager: self, bluetoothProvider: bluetoothProvider, colorPalette: colorPalette, allowedInsulinTypes: allowedInsulinTypes)
    }
    
    public static func createHUDView(rawValue: [String : Any]) -> BaseHUDView? {
        return DanaKitHUDProvider.createHUDView(rawValue: rawValue)
    }
    
    public static var onboardingImage: UIImage? {
        return UIImage(named: "danai", in: Bundle(for: DanaKitHUDProvider.self), compatibleWith: nil)
    }
    
    public var smallImage: UIImage? {
        return UIImage(named: state.getDanaPumpImageName(), in: Bundle(for: DanaKitHUDProvider.self), compatibleWith: nil)
    }
    
    public var pumpStatusHighlight: DeviceStatusHighlight? {
        return nil
    }
    
    public var pumpLifecycleProgress: DeviceLifecycleProgress? {
        return nil
    }
    
    public var pumpStatusBadge: DeviceStatusBadge? {
        return nil
    }
}
