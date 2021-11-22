//
//  Calibration.swift
//  MiaomiaoClient
//
//  Created by Bjørn Inge Berg on 05/03/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//

import Foundation
import os.log

private let LibreCalibrationLabel =  "https://LibreCalibrationLabelNative.doesnot.exist.com"
private let LibreCalibrationUrl = URL(string: LibreCalibrationLabel)!
private let LibreUsername = "LibreUsername"

fileprivate var logger = Logger(forType: "KeychainManagerCalibration")

public extension KeychainManagerWrapper {
    func setLibreNativeCalibrationData(_ calibrationData: SensorData.CalibrationInfo?) throws {
        var credentials: InternetCredentials? = nil
        if let calibrationData = calibrationData {
            credentials = InternetCredentials(username: LibreUsername, password: serializeNativeAlgorithmParameters(calibrationData), url: LibreCalibrationUrl)
        }
        logger.debug("dabear: Setting calibrationdata to \(String(describing: calibrationData))")
        try replaceInternetCredentials(credentials, forLabel: LibreCalibrationLabel)
    }

    func getLibreNativeCalibrationData() -> SensorData.CalibrationInfo? {
        do { // Silence all errors and return nil
            let credentials = try getInternetCredentials(label: LibreCalibrationLabel)
            return deserializeNativeAlgorithmParameters(text: credentials.password)
        } catch {

            return nil
        }
    }
}

public func calibrateSensor(sensordata: SensorData, callback: @escaping (SensorData.CalibrationInfo) -> Void) {
    
    let params = sensordata.calibrationData
    callback(params)
}

private func serializeNativeAlgorithmParameters(_ params: SensorData.CalibrationInfo) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted

    var aString = ""
    do {
        let jsonData = try encoder.encode(params)

        if let jsonString = String(data: jsonData, encoding: .utf8) {
            aString = jsonString
        }
    } catch {
        logger.debug("Could not serialize parameters: \(error.localizedDescription)")
    }
    return aString
}

private func deserializeNativeAlgorithmParameters(text: String) -> SensorData.CalibrationInfo? {
    if let jsonData = text.data(using: .utf8) {
        let decoder = JSONDecoder()

        do {
            return try decoder.decode(SensorData.CalibrationInfo.self, from: jsonData)
        } catch {
            logger.debug("Could not create instance: \(error.localizedDescription)")
        }
    } else {
        logger.debug("Did not create instance")
    }
    return nil
}
