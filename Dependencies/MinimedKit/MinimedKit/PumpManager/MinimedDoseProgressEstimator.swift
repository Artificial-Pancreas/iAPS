//
//  MinimedDoseProgressEstimator.swift
//  MinimedKit
//
//  Created by Pete Schwamb on 3/14/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

class MinimedDoseProgressEstimator: DoseProgressTimerEstimator {

    let dose: DoseEntry

    public let pumpModel: PumpModel

    override var progress: DoseProgress {
        let elapsed = -dose.startDate.timeIntervalSinceNow
        
        let (deliveredUnits, progress) = pumpModel.estimateBolusProgress(elapsed: elapsed, programmedUnits: dose.programmedUnits)

        return DoseProgress(deliveredUnits: deliveredUnits, percentComplete: progress)
    }

    init(dose: DoseEntry, pumpModel: PumpModel, reportingQueue: DispatchQueue) {
        self.dose = dose
        self.pumpModel = pumpModel
        super.init(reportingQueue: reportingQueue)
    }

    override func timerParameters() -> (delay: TimeInterval, repeating: TimeInterval) {
        let timeSinceStart = -dose.startDate.timeIntervalSinceNow
        let duration = dose.endDate.timeIntervalSince(dose.startDate)
        let timeBetweenPulses = duration / (Double(pumpModel.pulsesPerUnit) * dose.programmedUnits)

        let delayUntilNextPulse = timeBetweenPulses - timeSinceStart.remainder(dividingBy: timeBetweenPulses)
        
        return (delay: delayUntilNextPulse, repeating: timeBetweenPulses)
    }
}
