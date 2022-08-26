//
//  DeliveryUncertaintyRecoveryViewModel.swift
//  OmniKit
//
//  Created by Pete Schwamb on 8/25/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

class DeliveryUncertaintyRecoveryViewModel: PumpManagerStatusObserver {
    
    let appName: String
    let uncertaintyStartedAt: Date
    var respondToRecovery: Bool
    
    var onDismiss: (() -> Void)?
    var didRecover: (() -> Void)?
    var onDeactivate: (() -> Void)?
    
    init(appName: String, uncertaintyStartedAt: Date) {
        self.appName = appName
        self.uncertaintyStartedAt = uncertaintyStartedAt
        respondToRecovery = false
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        if !status.deliveryIsUncertain && respondToRecovery {
            didRecover?()
        }
    }
    
    func podDeactivationChosen() {
        self.onDeactivate?()
    }
}
