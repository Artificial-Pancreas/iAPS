//
//  SensorPairing.swift
//  LibreDirect
//
//  Created by Reimar Metzen on 06.07.21.
//
import Foundation
import Combine

class SensorPairingInfo : ObservableObject {
    @Published private(set) var uuid: Data
    @Published private(set) var patchInfo: Data
    @Published private(set) var fram: Data
    @Published private(set) var streamingEnabled: Bool

    public init(uuid: Data=Data(), patchInfo:Data=Data(), fram:Data=Data(), streamingEnabled: Bool = false) {
        self.uuid = uuid
        self.patchInfo = patchInfo
        self.fram = fram
        self.streamingEnabled = streamingEnabled
    }

    var sensorData : SensorData? {
        SensorData(bytes: [UInt8](self.fram))
    }

    var calibrationData : SensorData.CalibrationInfo? {
        sensorData?.calibrationData
    }

    

    
}

protocol SensorPairingProtocol {
    func pairSensor() -> AnyPublisher<SensorPairingInfo, Never>
}
