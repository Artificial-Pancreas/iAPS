//
//  BeepType.swift
//  OmniBLE
//
//  From OmniKit/Model/BeepType.swift
//  Created by Joseph Moran on 5/12/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation

//
// BeepType is used for the 0x19 Configure Alerts, 0x1E Set Beep Options and 0x1F Cancel Delivery commands.
// Some beep types values behave differently based on the command & circumstances due to Omnipod internals.
//
// Beep types 0x0, 0x9 & 0xA (as well as 0xE when the pod isn't suspended) will have no beeps or errors
// (when used in 0x19 Configure Alerts with an 'a' bit of 0 or 0x1F Cancel) and will return 0x6 Error
// response, code 7 (when used in 0x19 Configure Alerts with an 'a' bit of 1 or in 0x1E Beep Configure).
//
// Beep type 0xF will will have no beeps or errors (when used in 0x19 Configure Alerts
// or 0x1E Beep Configure), but will generate a 0x37 pod fault when used in 0x1F Cancel!
//
public enum BeepType: UInt8 {
    case noBeepCancel = 0x0 // silent for 0x1F Cancel & inactive 0x19 alerts; error for 0x1E Beep Options & active 0x19 alerts
    case beepBeepBeepBeep = 0x1
    case bipBeepBipBeepBipBeepBipBeep = 0x2
    case bipBip = 0x3
    case beep = 0x4
    case beepBeepBeep = 0x5
    case beeeeeep = 0x6
    case bipBipBipbipBipBip = 0x7
    case beeepBeeep = 0x8
    case unusedBeepType0x9 = 0x9 // silent for 0x1F Cancel & inactive 0x19 alerts; error for 0x1E Beep Options & active 0x19 alerts
    case unusedBeepType0xA = 0xA // silent for 0x1F Cancel & inactive 0x19 alerts; error for 0x1E Beep Options & active 0x19 alerts
    case beepBeep = 0xB
    case beeep = 0xC
    case bipBeeeeep = 0xD
    // If pod is currently suspended, 5 second beep for the 0x19, 0x1E & 0x1F commands
    // If pod is not suspended, silent for 0x1F Cancel & inactive 0x19 alerts; error for 0x1E Beep Options & active 0x19 alerts
    case fiveSecondBeep = 0xE
    case noBeepNonCancel = 0xF // silent for 0x1E Beep Options & 0x19 Configure Alerts, 0x37 pod fault for 0x1F Cancel!
}
