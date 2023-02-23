//
//  G7SettingsViewModel.swift
//  CGMBLEKitUI
//
//  Created by Pete Schwamb on 10/4/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import G7SensorKit
import LoopKit
import LoopKitUI
import HealthKit

public enum ColorStyle {
    case glucose, warning, critical, normal, dimmed
}

class G7SettingsViewModel: ObservableObject {
    @Published private(set) var scanning: Bool = false
    @Published private(set) var connected: Bool = false
    @Published private(set) var sensorName: String?
    @Published private(set) var activatedAt: Date?
    @Published private(set) var lastConnect: Date?
    @Published private(set) var latestReadingTimestamp: Date?
    @Published var uploadReadings: Bool = false {
        didSet {
            cgmManager.uploadReadings = uploadReadings
        }
    }
    
    var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable

    private var lastReading: G7GlucoseMessage?

    lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private lazy var glucoseFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: displayGlucoseUnitObservable.displayGlucoseUnit)
        formatter.numberFormatter.notANumberSymbol = "–"
        return formatter
    }()

    private let quantityFormatter = QuantityFormatter()

    private var cgmManager: G7CGMManager

    var progressBarState: G7ProgressBarState {
        switch cgmManager.lifecycleState {
        case .searching:
            return .searchingForSensor
        case .ok:
            return .lifetimeRemaining
        case .warmup:
            return .warmupProgress
        case .failed:
            return .sensorFailed
        case .gracePeriod:
            return .gracePeriodRemaining
        case .expired:
            return .sensorExpired
        }
    }

    init(cgmManager: G7CGMManager, displayGlucoseUnitObservable: DisplayGlucoseUnitObservable) {
        self.cgmManager = cgmManager
        self.displayGlucoseUnitObservable = displayGlucoseUnitObservable
        updateValues()

        self.cgmManager.addStateObserver(self, queue: DispatchQueue.main)
    }

    func updateValues() {
        scanning = cgmManager.isScanning
        sensorName = cgmManager.sensorName
        activatedAt = cgmManager.sensorActivatedAt
        connected = cgmManager.isConnected
        lastConnect = cgmManager.lastConnect
        lastReading = cgmManager.latestReading
        latestReadingTimestamp = cgmManager.latestReadingTimestamp
        uploadReadings = cgmManager.state.uploadReadings
    }

    var progressBarColorStyle: ColorStyle {
        switch progressBarState {
        case .warmupProgress:
            return .glucose
        case .searchingForSensor:
            return .dimmed
        case .sensorExpired, .sensorFailed:
            return .critical
        case .lifetimeRemaining:
            guard let remaining = progressValue else {
                return .dimmed
            }
            if remaining > .hours(24) {
                return .glucose
            } else {
                return .warning
            }
        case .gracePeriodRemaining:
            return .critical
        }
    }

    var progressBarProgress: Double {
        switch progressBarState {
        case .searchingForSensor:
            return 0
        case .warmupProgress:
            guard let value = progressValue, value > 0 else {
                return 0
            }
            return 1 - value / G7Sensor.warmupDuration
        case .lifetimeRemaining:
            guard let value = progressValue, value > 0 else {
                return 0
            }
            return 1 - value / G7Sensor.lifetime
        case .gracePeriodRemaining:
            guard let value = progressValue, value > 0 else {
                return 0
            }
            return 1 - value / G7Sensor.gracePeriod
        case .sensorExpired, .sensorFailed:
            return 1
        }
    }

    var progressReferenceDate: Date? {
        switch progressBarState {
        case .searchingForSensor:
            return nil
        case .sensorExpired, .gracePeriodRemaining:
            return cgmManager.sensorEndsAt
        case .warmupProgress:
            return cgmManager.sensorFinishesWarmupAt
        case .lifetimeRemaining:
            return cgmManager.sensorExpiresAt
        case .sensorFailed:
            return nil
        }
    }

    var progressValue: TimeInterval? {
        switch progressBarState {
        case .sensorExpired, .sensorFailed, .searchingForSensor:
            guard let sensorEndsAt = cgmManager.sensorEndsAt else {
                return nil
            }
            return sensorEndsAt.timeIntervalSinceNow
        case .warmupProgress:
            guard let warmupFinishedAt = cgmManager.sensorFinishesWarmupAt else {
                return nil
            }
            return max(0, warmupFinishedAt.timeIntervalSinceNow)
        case .lifetimeRemaining:
            guard let expiration = cgmManager.sensorExpiresAt else {
                return nil
            }
            return max(0, expiration.timeIntervalSinceNow)
        case .gracePeriodRemaining:
            guard let sensorEndsAt = cgmManager.sensorEndsAt else {
                return nil
            }
            return max(0, sensorEndsAt.timeIntervalSinceNow)
        }
    }

    func scanForNewSensor() {
        cgmManager.scanForNewSensor()
    }

    var lastGlucoseString: String {
        guard let lastReading = lastReading, lastReading.hasReliableGlucose, let quantity = lastReading.glucoseQuantity else {
            return LocalizedString("– – –", comment: "No glucose value representation (3 dashes for mg/dL)")
        }

        switch lastReading.glucoseRangeCategory {
        case .some(.belowRange):
            return LocalizedString("LOW", comment: "String displayed instead of a glucose value below the CGM range")
        case .some(.aboveRange):
            return LocalizedString("HIGH", comment: "String displayed instead of a glucose value above the CGM range")
        default:
            quantityFormatter.setPreferredNumberFormatter(for: displayGlucoseUnitObservable.displayGlucoseUnit)
            let valueStr = quantityFormatter.string(from: quantity, for: displayGlucoseUnitObservable.displayGlucoseUnit, includeUnit: false) ?? ""
            return String(format: "%@ %@", valueStr, displayGlucoseUnitObservable.displayGlucoseUnit.shortLocalizedUnitString())
        }
    }

    var lastGlucoseTrendString: String {
        if let lastReading = lastReading, lastReading.hasReliableGlucose, let trendRate = lastReading.trendRate {
            let glucoseUnitPerMinute = displayGlucoseUnitObservable.displayGlucoseUnit.unitDivided(by: .minute())
            // This seemingly strange replacement of glucose units is only to display the unit string correctly
            let trendPerMinute = HKQuantity(unit: displayGlucoseUnitObservable.displayGlucoseUnit, doubleValue: trendRate.doubleValue(for: glucoseUnitPerMinute))
            let formatted = glucoseFormatter.string(from: trendPerMinute, for: displayGlucoseUnitObservable.displayGlucoseUnit)!
            return String(format: LocalizedString("%@/min", comment: "Format string for glucose trend per minute. (1: glucose value and unit)"), formatted)
        } else {
            return ""
        }
    }
}

extension G7SettingsViewModel: G7StateObserver {
    func g7StateDidUpdate(_ state: G7CGMManagerState?) {
        updateValues()
    }

    func g7ConnectionStatusDidChange() {
        updateValues()
    }
}
