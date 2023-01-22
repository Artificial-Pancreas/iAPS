//
//  ShareClientManager+UI.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit
import ShareClient

extension ShareClientManager: CGMManagerUI {
    public static var onboardingImage: UIImage? {
        return nil
    }
    
    public static func setupViewController(bluetoothProvider: BluetoothProvider, displayGlucoseUnitObservable: DisplayGlucoseUnitObservable, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> SetupUIResult<CGMManagerViewController, CGMManagerUI> {
        return .userInteractionRequired(ShareClientSetupViewController())
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider, displayGlucoseUnitObservable: DisplayGlucoseUnitObservable, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) ->CGMManagerViewController {
        let settings = ShareClientSettingsViewController(cgmManager: self, displayGlucoseUnitObservable: displayGlucoseUnitObservable, allowsDeletion: true)
        let nav = CGMManagerSettingsNavigationViewController(rootViewController: settings)
        return nav
    }

    public var smallImage: UIImage? {
        return nil
    }

    // TODO Placeholder.
    public var cgmStatusHighlight: DeviceStatusHighlight? {
        return nil
    }

    // TODO Placeholder.
    public var cgmStatusBadge: DeviceStatusBadge? {
        return nil
    }

    // TODO Placeholder.
    public var cgmLifecycleProgress: DeviceLifecycleProgress? {
        return nil
    }
}
