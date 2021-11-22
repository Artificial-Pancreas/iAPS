//
//  GlucoseFromRaw.swift
//

import Foundation
import RawGlucose

extension MeasurementProtocol {
    func roundedGlucoseValueFromRaw(calibrationInfo: SensorData.CalibrationInfo) -> Int {
        Int(round(glucoseValueFromRaw(calibrationInfo: calibrationInfo)))
    }

    func roundedGlucoseValueFromRaw2(calibrationInfo: SensorData.CalibrationInfo) -> Double{
        round(glucoseValueFromRaw(calibrationInfo: calibrationInfo))
    }

    
    func glucoseValueFromRaw(calibrationInfo: SensorData.CalibrationInfo) -> Double {
        RawGlucose.glucoseValueFromRaw(
            rawTemperature: Double(self.rawTemperature),
            rawTemperatureAdjustment: Double(self.rawTemperatureAdjustment),
            rawGlucose: Double(self.rawGlucose),
            i1: calibrationInfo.i1,
            i2: calibrationInfo.i2,
            i3: calibrationInfo.i3,
            i4: calibrationInfo.i4,
            i5: calibrationInfo.i5,
            i6: calibrationInfo.i6
        )
    }
}

