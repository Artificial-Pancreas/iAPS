//
//  BasalProfileViewModel.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 05/03/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKit

class BasalProfileViewModel : ObservableObject {
    @Published var basalProfileNumber: UInt8 = 0
    @Published var loading: Bool = false
    
    private let pumpManager: DanaKitPumpManager?
        
    init(_ pumpManager: DanaKitPumpManager?) {
        self.pumpManager = pumpManager
        
        self.basalProfileNumber = pumpManager?.state.basalProfileNumber ?? 0
    }
    
    func basalProfileNumberChanged(completion: @escaping () -> Void) {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        self.loading = true
        pumpManager.state.basalProfileNumber = self.basalProfileNumber
        pumpManager.switchBasalProfileSlot(basal: pumpManager.state.basalSchedule, completion: { _ in
            DispatchQueue.main.async {
                self.loading = false
                completion()
            }
        })
    }
}
