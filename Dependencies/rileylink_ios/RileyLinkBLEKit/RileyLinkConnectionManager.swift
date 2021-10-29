//
//  RileyLinkConnectionManager.swift
//  RileyLinkBLEKit
//
//  Created by Pete Schwamb on 8/16/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public protocol RileyLinkConnectionManagerDelegate : AnyObject {
    func rileyLinkConnectionManager(_ rileyLinkConnectionManager: RileyLinkConnectionManager, didChange state: RileyLinkConnectionManagerState)
}

public class RileyLinkConnectionManager {
    
    public typealias RawStateValue = [String : Any]

    /// The current, serializable state of the manager
    public var rawState: RawStateValue {
        return state.rawValue
    }
    
    public private(set) var state: RileyLinkConnectionManagerState {
        didSet {
            delegate?.rileyLinkConnectionManager(self, didChange: state)
        }
    }

    public var deviceProvider: RileyLinkDeviceProvider {
        return rileyLinkDeviceManager
    }
    
    public weak var delegate: RileyLinkConnectionManagerDelegate?
    
    private let rileyLinkDeviceManager: RileyLinkDeviceManager
    
    private var autoConnectIDs: Set<String> {
        get {
            return state.autoConnectIDs
        }
        set {
            state.autoConnectIDs = newValue
        }
    }
    
    public init(state: RileyLinkConnectionManagerState) {
        self.rileyLinkDeviceManager = RileyLinkDeviceManager(autoConnectIDs: state.autoConnectIDs)
        self.state = state
    }
    
    public init(autoConnectIDs: Set<String>) {
        self.rileyLinkDeviceManager = RileyLinkDeviceManager(autoConnectIDs: autoConnectIDs)
        self.state = RileyLinkConnectionManagerState(autoConnectIDs: autoConnectIDs)
    }
    
    public convenience init?(rawValue: RawStateValue) {
        if let state = RileyLinkConnectionManagerState(rawValue: rawValue) {
            self.init(state: state)
        } else {
            return nil
        }
    }
    
    public var connectingCount: Int {
        return self.autoConnectIDs.count
    }
    
    public func shouldConnect(to deviceID: String) -> Bool {
        return self.autoConnectIDs.contains(deviceID)
    }
    
    public func connect(_ device: RileyLinkDevice) {
        autoConnectIDs.insert(device.peripheralIdentifier.uuidString)
        rileyLinkDeviceManager.connect(device)
    }
    
    public func disconnect(_ device: RileyLinkDevice) {
        autoConnectIDs.remove(device.peripheralIdentifier.uuidString)
        rileyLinkDeviceManager.disconnect(device)
    }

    public func setScanningEnabled(_ enabled: Bool) {
        rileyLinkDeviceManager.setScanningEnabled(enabled)
    }
}

public protocol RileyLinkDeviceProvider: AnyObject {
    func getDevices(_ completion: @escaping (_ devices: [RileyLinkDevice]) -> Void)
    var idleListeningEnabled: Bool { get }
    var timerTickEnabled: Bool { get set }
    func deprioritize(_ device: RileyLinkDevice, completion: (() -> Void)?)
    func assertIdleListening(forcingRestart: Bool)
    var idleListeningState: RileyLinkDevice.IdleListeningState { get set }

    var debugDescription: String { get }
}

extension RileyLinkDeviceManager: RileyLinkDeviceProvider {}
