//
//  PumpOps.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/14/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation
import RileyLinkKit
import RileyLinkBLEKit
import os.log
import LoopKit


public protocol PumpOpsDelegate: class {
    // TODO: Audit clients of this as its called on the session queue
    func pumpOps(_ pumpOps: PumpOps, didChange state: PumpState)
}


public class PumpOps {
    private let log = OSLog(category: "PumpOps")

    public let pumpSettings: PumpSettings

    public let pumpState: Locked<PumpState>

    private let configuredDevices: Locked<Set<RileyLinkDevice>> = Locked(Set())

    // Isolated to RileyLinkDeviceManager.sessionQueue
    private var sessionDevice: RileyLinkDevice?

    private weak var delegate: PumpOpsDelegate?
    
    public init(pumpSettings: PumpSettings, pumpState: PumpState?, delegate: PumpOpsDelegate?) {
        self.pumpSettings = pumpSettings
        self.delegate = delegate

        if let pumpState = pumpState {
            self.pumpState = Locked(pumpState)
        } else {
            let pumpState = PumpState()
            self.pumpState = Locked(pumpState)
            self.delegate?.pumpOps(self, didChange: pumpState)
        }
    }

    public func runSession(withName name: String, using deviceSelector: @escaping (_ completion: @escaping (_ device: RileyLinkDevice?) -> Void) -> Void, _ block: @escaping (_ session: PumpOpsSession?) -> Void) {
        deviceSelector { (device) in
            guard let device = device else {
                block(nil)
                return
            }

            self.runSession(withName: name, using: device, block)
        }
    }

    public func runSession(withName name: String, using device: RileyLinkDevice, _ block: @escaping (_ session: PumpOpsSession) -> Void) {
        device.runSession(withName: name) { (commandSession) in
            let session = PumpOpsSession(settings: self.pumpSettings, pumpState: self.pumpState.value, session: commandSession, delegate: self)
            self.sessionDevice = device
            if !commandSession.firmwareVersion.isUnknown {
                self.configureDevice(device, with: session)
            } else {
                self.log.error("Skipping device configuration due to unknown firmware version")
            }

            block(session)
            self.sessionDevice = nil
        }
    }

    // Must be called from within the RileyLinkDevice sessionQueue
    private func configureDevice(_ device: RileyLinkDevice, with session: PumpOpsSession) {
        guard !self.configuredDevices.value.contains(device) else {
            return
        }

        log.default("Configuring RileyLinkDevice: %{public}@", String(describing: device.deviceURI))

        do {
            _ = try session.configureRadio(for: pumpSettings.pumpRegion, frequency: pumpState.value.lastValidFrequency)
        } catch let error {
            // Ignore the error and let the block run anyway
            log.error("Error configuring device: %{public}@", String(describing: error))
            return
        }

        NotificationCenter.default.post(name: .DeviceRadioConfigDidChange, object: device)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceRadioConfigDidChange(_:)), name: .DeviceRadioConfigDidChange, object: device)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceRadioConfigDidChange(_:)), name: .DeviceConnectionStateDidChange, object: device)
        _ = configuredDevices.mutate { (value) in
            value.insert(device)
        }
    }

    @objc private func deviceRadioConfigDidChange(_ note: Notification) {
        guard let device = note.object as? RileyLinkDevice else {
            return
        }

        NotificationCenter.default.removeObserver(self, name: .DeviceRadioConfigDidChange, object: device)
        NotificationCenter.default.removeObserver(self, name: .DeviceConnectionStateDidChange, object: device)

        _ = configuredDevices.mutate { (value) in
            value.remove(device)
        }
    }
}

// Delivered on RileyLinkDeviceManager.sessionQueue
extension PumpOps: PumpOpsSessionDelegate {
    func pumpOpsSessionDidChangeRadioConfig(_ session: PumpOpsSession) {
        if let sessionDevice = self.sessionDevice {
            self.configuredDevices.value = [sessionDevice]
        }
    }
    
    func pumpOpsSession(_ session: PumpOpsSession, didChange state: PumpState) {
        self.pumpState.value = state
        delegate?.pumpOps(self, didChange: state)
        NotificationCenter.default.post(
            name: .PumpOpsStateDidChange,
            object: self,
            userInfo: [PumpOps.notificationPumpStateKey: pumpState]
        )
    }
}


extension PumpOps: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "### PumpOps",
            "pumpSettings: \(String(reflecting: pumpSettings))",
            "pumpState: \(String(reflecting: pumpState.value))",
            "configuredDevices: \(configuredDevices.value.map({ $0.peripheralIdentifier.uuidString }))",
        ].joined(separator: "\n")
    }
}


/// Provide a notification contract that clients can use to inform RileyLink UI of changes to PumpOps.PumpState
extension PumpOps {
    public static let notificationPumpStateKey = "com.rileylink.RileyLinkKit.PumpOps.PumpState"
}


extension Notification.Name {
    public static let PumpOpsStateDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkKit.PumpOpsStateDidChange")
}
