//
//  GlucoseEntry.swift
//  NightscoutUploadKit
//
//  Created by Pete Schwamb on 4/19/20.
//  Copyright © 2020 Pete Schwamb. All rights reserved.
//
import Foundation

public struct GlucoseEntry {
    typealias RawValue = [String: Any]

    public enum GlucoseType: String {
        case meter
        case sensor
    }

    public enum GlucoseTrend: Int, CaseIterable {
        case upUpUp         = 1
        case upUp           = 2
        case up             = 3
        case flat           = 4
        case down           = 5
        case downDown       = 6
        case downDownDown   = 7
        case notComputable  = 8
        case rateOutOfRange = 9
        
        init?(direction: String) {
            for trend in GlucoseTrend.allCases {
                if direction == trend.direction {
                    self = trend
                    return
                }
            }
            return nil
        }

        public var direction: String {
            switch self {
            case .upUpUp:
                return "DoubleUp"
            case .upUp:
                return "SingleUp"
            case .up:
                return "FortyFiveUp"
            case .flat:
                return "Flat"
            case .down:
                return "FortyFiveDown"
            case .downDown:
                return "SingleDown"
            case .downDownDown:
                return "DoubleDown"
            case .notComputable:
                return "NotComputable"
            case .rateOutOfRange:
                return "RateOutOfRange"
            }
        }
    }


    public let id: String?
    public let glucose: Double
    public let date: Date
    public let device: String?
    public let glucoseType: GlucoseType
    public let trend: GlucoseTrend?
    public let changeRate: Double?
    public let isCalibration: Bool?

    public init(glucose: Double, date: Date, device: String?, glucoseType: GlucoseType = .sensor, trend: GlucoseTrend? = nil, changeRate: Double?, isCalibration: Bool? = false, id: String? = nil) {
        self.glucose = glucose
        self.date = date
        self.device = device
        self.glucoseType = glucoseType
        self.trend = trend
        self.changeRate = changeRate
        self.isCalibration = isCalibration
        self.id = id
    }

    public var dictionaryRepresentation: [String: Any] {
        var representation: [String: Any] = [
            "date": date.timeIntervalSince1970 * 1000,
            "dateString": TimeFormat.timestampStrFromDate(date)
        ]

        representation["device"] = device
        representation["_id"] = id

        switch glucoseType {
        case .meter:
            representation["type"] = "mbg"
            representation["mbg"] = glucose
        case .sensor:
            representation["type"] = "sgv"
            representation["sgv"] = glucose
        }

        if let trend = trend {
            representation["trend"] = trend.rawValue
            representation["direction"] = trend.direction
        }

        representation["trendRate"] = changeRate
        representation["isCalibration"] = isCalibration

        return representation
    }

    init?(rawValue: RawValue) {

        guard
            let id = rawValue["_id"] as? String,
            let epoch = rawValue["date"] as? Double
        else {
            return nil
        }

        self.id = id
        self.date = Date(timeIntervalSince1970: epoch / 1000.0)
        self.device = rawValue["device"] as? String

        //Dexcom changed the format of trend in 2021 so we accept both String/Int types
        if let intTrend = rawValue["trend"] as? Int {
            self.trend = GlucoseTrend(rawValue: intTrend)
        } else if let stringTrend = rawValue["trend"] as? String, let intTrend = Int(stringTrend) {
            self.trend = GlucoseTrend(rawValue: intTrend)
        } else if let directionString = rawValue["direction"] as? String {
            self.trend = GlucoseTrend(direction: directionString)
        } else {
            self.trend = nil
        }

        if let sgv = rawValue["sgv"] as? Double {
            self.glucose = sgv
            self.glucoseType = .sensor
        } else if let mbg = rawValue["mbg"] as? Double {
            self.glucose = mbg
            self.glucoseType = .meter
        } else {
            return nil
        }

        self.changeRate = rawValue["trendRate"] as? Double
        self.isCalibration = rawValue["isCalibration"] as? Bool
    }
}
