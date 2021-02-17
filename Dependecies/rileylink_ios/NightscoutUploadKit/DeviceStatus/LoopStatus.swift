//
//  LoopStatus.swift
//  RileyLink
//
//  Created by Pete Schwamb on 7/26/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation
import HealthKit

public struct LoopStatus {
    let name: String
    let version: String
    let timestamp: Date

    let iob: IOBStatus?
    let cob: COBStatus?
    let predicted: PredictedBG?
    let automaticDoseRecommendation: AutomaticDoseRecommendation?
    let recommendedBolus: Double?
    let enacted: LoopEnacted?
    let rileylinks: [RileyLinkStatus]?
    let failureReason: Error?
    let currentCorrectionRange: CorrectionRange?
    let forecastError: ForecastError?
    let testingDetails: [String: Any]?

    public init(name: String, version: String, timestamp: Date, iob: IOBStatus? = nil, cob: COBStatus? = nil, predicted: PredictedBG? = nil, automaticDoseRecommendation: AutomaticDoseRecommendation? = nil, recommendedBolus: Double? = nil, enacted: LoopEnacted? = nil, rileylinks: [RileyLinkStatus]? = nil, failureReason: Error? = nil, currentCorrectionRange: CorrectionRange? = nil, forecastError: ForecastError? = nil, testingDetails: [String: Any]? = nil) {
        self.name = name
        self.version = version
        self.timestamp = timestamp
        self.iob = iob
        self.cob = cob
        self.predicted = predicted
        self.automaticDoseRecommendation = automaticDoseRecommendation
        self.recommendedBolus = recommendedBolus
        self.enacted = enacted
        self.rileylinks = rileylinks
        self.failureReason = failureReason
        self.currentCorrectionRange = currentCorrectionRange
        self.forecastError = forecastError
        self.testingDetails = testingDetails
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()
        
        rval["name"] = name
        rval["version"] = version
        rval["timestamp"] = TimeFormat.timestampStrFromDate(timestamp)

        if let iob = iob {
            rval["iob"] = iob.dictionaryRepresentation
        }

        if let cob = cob {
            rval["cob"] = cob.dictionaryRepresentation
        }
        
        if let predicted = predicted {
            rval["predicted"] = predicted.dictionaryRepresentation
        }

        if let automaticDoseRecommendation = automaticDoseRecommendation {
            rval["automaticDoseRecommendation"] = automaticDoseRecommendation.dictionaryRepresentation
        }

        if let recommendedBolus = recommendedBolus {
            rval["recommendedBolus"] = recommendedBolus
        }
        
        if let enacted = enacted {
            rval["enacted"] = enacted.dictionaryRepresentation
        }
        
        if let failureReason = failureReason {
            rval["failureReason"] = String(describing: failureReason)
        }

        if let rileylinks = rileylinks {
            rval["rileylinks"] = rileylinks.map { $0.dictionaryRepresentation }
        }

        if let currentCorrectionRange = currentCorrectionRange {
            rval["currentCorrectionRange"] = currentCorrectionRange.dictionaryRepresentation
        }
        
        if let forecastError = forecastError {
            rval["forecastError"] = forecastError.dictionaryRepresentation
        }
        
        if let testingDetails = testingDetails {
            rval["testingDetails"] = testingDetails
        }

        return rval
    }
}

