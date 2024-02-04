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
    @Published var beepAndAlarm: UInt8
    @Published var lcdOnTimeInSec: UInt8
    @Published var backlightOnTimInSec: UInt8
    
    private let pumpManager: DanaKitPumpManager?
    
    init(_ pumpManager: DanaKitPumpManager?) {
        self.pumpManager = pumpManager
        
        self.lowReservoirRate = self.pumpManager?.state.lowReservoirRate ?? 0
        self.isTimeDisplay24H = self.pumpManager?.state.isTimeDisplay24H ?? false
        self.isButtonScrollOnOff = self.pumpManager?.state.isButtonScrollOnOff ?? false
        self.beepAndAlarm = self.pumpManager?.state.beepAndAlarm ?? 0
        self.lcdOnTimeInSec = self.pumpManager?.state.lcdOnTimeInSec ?? 0
        self.backlightOnTimInSec = self.pumpManager?.state.backlightOnTimInSec ?? 0
    }
    
    func storeUserOption() {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        self.storingUseroption = true
        let model = PacketGeneralSetUserOption(
            isTimeDisplay24H: self.isTimeDisplay24H,
            isButtonScrollOnOff: self.isButtonScrollOnOff,
            beepAndAlarm: self.beepAndAlarm,
            lcdOnTimeInSec: self.lcdOnTimeInSec,
            backlightOnTimInSec: self.backlightOnTimInSec,
            selectedLanguage: pumpManager.state.selectedLanguage,
            units: pumpManager.state.units,
            shutdownHour: pumpManager.state.shutdownHour,
            lowReservoirRate: self.lowReservoirRate,
            cannulaVolume: pumpManager.state.cannulaVolume,
            refillAmount: pumpManager.state.refillAmount,
            selectableLanguage1: pumpManager.state.selectableLanguage1,
            selectableLanguage2: pumpManager.state.selectableLanguage2,
            selectableLanguage3: pumpManager.state.selectableLanguage3,
            selectableLanguage4: pumpManager.state.selectableLanguage4,
            selectableLanguage5: pumpManager.state.selectableLanguage5
        )
        
        self.pumpManager?.setUserSettings(data: model, completion: { err in
            DispatchQueue.main.async {
                self.storingUseroption = false
            }
        })
    }
}
