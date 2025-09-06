//
//  DoseProgressEstimator.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 23/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation
import LoopKit

class DanaKitDoseProgressReporter: DoseProgressReporter {
    var progress: DoseProgress {
        return DoseProgress(deliveredUnits: self.deliveredUnits, percentComplete: self.deliveredUnits / self.total)
    }
    
    private var observers = WeakSet<DoseProgressObserver>()

    private let total: Double
    private var deliveredUnits: Double = 0

    public init(total: Double) {
        self.total = total
    }

    public func addObserver(_ observer: DoseProgressObserver) {
        observers.insert(observer)
    }

    public func removeObserver(_ observer: DoseProgressObserver) {
        observers.remove(observer)
    }

    public func notify(deliveredUnits: Double) {
        self.deliveredUnits = deliveredUnits
        
        DispatchQueue.main.async {
            for observer in self.observers {
                observer.doseProgressReporterDidUpdate(self)
            }
        }
    }
}
