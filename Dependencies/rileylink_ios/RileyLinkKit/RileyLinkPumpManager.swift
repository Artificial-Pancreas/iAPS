//
//  RileyLinkPumpManager.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopKit
import RileyLinkBLEKit

open class RileyLinkPumpManager {
    
    public init(rileyLinkDeviceProvider: RileyLinkDeviceProvider,
                rileyLinkConnectionManager: RileyLinkConnectionManager? = nil) {
        
        self.rileyLinkDeviceProvider = rileyLinkDeviceProvider
        self.rileyLinkConnectionManager = rileyLinkConnectionManager
        self.rileyLinkConnectionManagerState = rileyLinkConnectionManager?.state
        
        // Listen for device notifications
        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkPacketNotification(_:)), name: .DevicePacketReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkTimerTickNotification(_:)), name: .DeviceTimerDidTick, object: nil)
    }
    
    /// Manages all the RileyLinks - access to management is optional
    public let rileyLinkConnectionManager: RileyLinkConnectionManager?

    // TODO: Not thread-safe
    open var rileyLinkConnectionManagerState: RileyLinkConnectionManagerState?
    
    /// Access to rileylink devices
    public let rileyLinkDeviceProvider: RileyLinkDeviceProvider

    // TODO: Put this on each RileyLinkDevice?
    private var lastTimerTick = Locked(Date.distantPast)

    /// Called when one of the connected devices receives a packet outside of a session
    ///
    /// - Parameters:
    ///   - device: The device
    ///   - packet: The received packet
    open func device(_ device: RileyLinkDevice, didReceivePacket packet: RFPacket) { }

    open func deviceTimerDidTick(_ device: RileyLinkDevice) { }

    // MARK: - CustomDebugStringConvertible
    
    open var debugDescription: String {
        return [
            "## RileyLinkPumpManager",
            "rileyLinkConnectionManager: \(String(reflecting: rileyLinkConnectionManager))",
            "lastTimerTick: \(String(describing: lastTimerTick.value))",
            "",
            String(reflecting: rileyLinkDeviceProvider),
        ].joined(separator: "\n")
    }
}

// MARK: - RileyLink Updates
extension RileyLinkPumpManager {

    /**
     Called when a new idle message is received by the RileyLink.

     Only MySentryPumpStatus messages are handled.

     - parameter note: The notification object
     */
    @objc private func receivedRileyLinkPacketNotification(_ note: Notification) {
        guard let device = note.object as? RileyLinkDevice,
            let packet = note.userInfo?[RileyLinkDevice.notificationPacketKey] as? RFPacket
        else {
            return
        }

        device.assertOnSessionQueue()

        self.device(device, didReceivePacket: packet)
    }

    @objc private func receivedRileyLinkTimerTickNotification(_ note: Notification) {
        guard let device = note.object as? RileyLinkDevice else {
            return
        }

        self.lastTimerTick.value = Date()
        self.deviceTimerDidTick(device)
    }
    
    open func connectToRileyLink(_ device: RileyLinkDevice) {
        rileyLinkConnectionManager?.connect(device)
    }

    open func disconnectFromRileyLink(_ device: RileyLinkDevice) {
        rileyLinkConnectionManager?.disconnect(device)
    }
    
}

// MARK: - RileyLinkConnectionManagerDelegate
extension RileyLinkPumpManager: RileyLinkConnectionManagerDelegate {
    public func rileyLinkConnectionManager(_ rileyLinkConnectionManager: RileyLinkConnectionManager, didChange state: RileyLinkConnectionManagerState) {
        self.rileyLinkConnectionManagerState = state
    }
}


