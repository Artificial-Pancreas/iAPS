import Foundation

enum Calibrations {
    enum Config {
        static let maxLatestReadingAge: TimeInterval = .minutes(4.5)
        static let maxInterpolationGap: TimeInterval = .minutes(10)
        static let stabilityWindow: TimeInterval = .minutes(15)
        static let maxStableRate: Double = 1.0
    }

    struct Item: Hashable, Identifiable {
        let calibration: Calibration

        var id: String {
            calibration.id.uuidString
        }
    }

    struct PairedReading: Equatable {
        let uncalibrated: Double
        let rate: Double?

        var isStable: Bool {
            guard let rate else { return true }
            return abs(rate) <= Config.maxStableRate
        }
    }

    enum LookupError: Error, Equatable {
        case noGlucose
        case staleGlucose
        case beforeHistory
        case gapTooLarge
        case differentSensorSession

        var message: String {
            switch self {
            case .noGlucose:
                return NSLocalizedString("No CGM readings are stored yet.", comment: "Calibration lookup error")
            case .staleGlucose:
                return NSLocalizedString(
                    "The latest CGM reading is more than 5 minutes old. Wait for a new reading, or enter the time the meter reading was taken.",
                    comment: "Calibration lookup error"
                )
            case .beforeHistory:
                return NSLocalizedString(
                    "There is no CGM reading stored for that time. Only the last 24 hours are available.",
                    comment: "Calibration lookup error"
                )
            case .gapTooLarge:
                return NSLocalizedString(
                    "There is a gap in the CGM readings around that time.",
                    comment: "Calibration lookup error"
                )
            case .differentSensorSession:
                return NSLocalizedString(
                    "That time belongs to a previous sensor session.",
                    comment: "Calibration lookup error"
                )
            }
        }
    }

    enum RawGlucoseLookup {
        private static func sensorReadings(_ readings: [BloodGlucose]) -> [BloodGlucose] {
            readings.filter { $0.type == GlucoseType.sgv.rawValue }
        }

        /// date: the moment the meter reading was taken
        /// readings: the stored raw readings, newest -> oldest
        static func value(at date: Date, in readings: [BloodGlucose]) -> Result<Double, LookupError> {
            sensorValue(at: date, in: sensorReadings(readings))
        }

        /// Whether a past reading can be attributed to the sensor that is running now.
        private static func belongsToCurrentSession(
            _ reading: BloodGlucose,
            _ currentSession: Date?,
            historyReportsSessions: Bool
        ) -> Bool {
            guard let currentSession else { return !historyReportsSessions }
            guard let readingSession = reading.sessionStartDate else { return false }
            return BloodGlucose.isSameSession(readingSession, currentSession)
        }

        private static func sensorValue(at date: Date, in readings: [BloodGlucose]) -> Result<Double, LookupError> {
            guard let newest = readings.first, let oldest = readings.last else {
                return .failure(.noGlucose)
            }

            // after the newest reading: only acceptable while that reading is still current
            if date > newest.dateString {
                guard date.timeIntervalSince(newest.dateString) <= Config.maxLatestReadingAge else {
                    return .failure(.staleGlucose)
                }
                return .success(Double(newest.uncalibrated))
            }

            guard date >= oldest.dateString else {
                return .failure(.beforeHistory)
            }

            // readings are newest -> oldest
            guard let index = readings.firstIndex(where: { $0.dateString <= date }) else {
                return .failure(.beforeHistory)
            }

            let before = readings[index]

            guard index > 0 else {
                return .success(Double(before.uncalibrated))
            }

            let currentSession = newest.sessionStartDate
            let historyReportsSessions = readings.contains { $0.sessionStartDate != nil }

            let after = readings[index - 1]

            for reading in [before, after] {
                guard belongsToCurrentSession(reading, currentSession, historyReportsSessions: historyReportsSessions)
                else {
                    return .failure(.differentSensorSession)
                }
            }
            let span = after.dateString.timeIntervalSince(before.dateString)

            guard span <= Config.maxInterpolationGap else {
                return .failure(.gapTooLarge)
            }
            guard span > 0 else {
                return .success(Double(before.uncalibrated))
            }

            let fraction = date.timeIntervalSince(before.dateString) / span
            let from = Double(before.uncalibrated)
            let to = Double(after.uncalibrated)

            return .success(from + fraction * (to - from))
        }

        static func rate(around date: Date, in readings: [BloodGlucose]) -> Double? {
            let window = Config.stabilityWindow
            let minutes = window / 60
            let sensor = sensorReadings(readings)

            if case let .success(earlier) = sensorValue(at: date - window, in: sensor),
               case let .success(later) = sensorValue(at: date + window, in: sensor)
            {
                return (later - earlier) / (2 * minutes)
            }

            if case let .success(earlier) = sensorValue(at: date - window, in: sensor),
               case let .success(now) = sensorValue(at: date, in: sensor)
            {
                return (now - earlier) / minutes
            }

            return nil
        }
    }
}

protocol CalibrationsProvider: Provider {}
