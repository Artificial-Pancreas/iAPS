//
//  DanaKitUserSettingsViewModel.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 29/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation
import LoopKit

class DanaKitUserSettingsViewModel : ObservableObject {
    @Published var storingUseroption = false
    @Published var lowReservoirRate: UInt8
    @Published var isTimeDisplay24H: Bool
    @Published var isButtonScrollOnOff: Bool
    @Published var beepAndAlarm: BeepAlarmType
    @Published var lcdOnTimeInSec: UInt8
    @Published var backlightOnTimeInSec: UInt8
    @Published var refillAmount: UInt16
    
    private let pumpManager: DanaKitPumpManager?
    
    init(_ pumpManager: DanaKitPumpManager?) {
        self.pumpManager = pumpManager
        
        self.lowReservoirRate = self.pumpManager?.state.lowReservoirRate ?? 0
        self.isTimeDisplay24H = self.pumpManager?.state.isTimeDisplay24H ?? false
        self.isButtonScrollOnOff = self.pumpManager?.state.isButtonScrollOnOff ?? false
        self.beepAndAlarm = self.pumpManager?.state.beepAndAlarm ?? .sound
        self.lcdOnTimeInSec = self.pumpManager?.state.lcdOnTimeInSec ?? 0
        self.backlightOnTimeInSec = self.pumpManager?.state.backlightOnTimInSec ?? 0
        self.refillAmount = self.pumpManager?.state.refillAmount ?? 0
    }
    
    func storeUserOption() {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        self.storingUseroption = true
        let model = PacketGeneralSetUserOption(
            isTimeDisplay24H: self.isTimeDisplay24H,
            isButtonScrollOnOff: self.isButtonScrollOnOff,
            beepAndAlarm: self.beepAndAlarm.rawValue,
            lcdOnTimeInSec: self.lcdOnTimeInSec,
            backlightOnTimeInSec: self.backlightOnTimeInSec,
            selectedLanguage: pumpManager.state.selectedLanguage,
            units: pumpManager.state.units,
            shutdownHour: pumpManager.state.shutdownHour,
            lowReservoirRate: self.lowReservoirRate,
            cannulaVolume: pumpManager.state.cannulaVolume,
            refillAmount: self.refillAmount,
            targetBg: pumpManager.state.targetBg
        )
        
        pumpManager.setUserSettings(data: model, completion: { err in
            DispatchQueue.main.async {
                self.storingUseroption = false
            }
        })
    }
}
