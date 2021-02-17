//
//  BeepType.swift
//  OmniKit
//
//  Created by Joseph Moran on 5/12/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation

// BeepType is used for the $19 Configure Alerts and $1F Cancel Commands
// Values 1 thru 8 are exactly the same as in BeepConfigType below
// N.B. for BeepType, noBeep is 0x0, while for BeepConfigType it is 0xF
public enum BeepType: UInt8 {
    case noBeep = 0x0
    case beepBeepBeepBeep = 0x1
    case bipBeepBipBeepBipBeepBipBeep = 0x2
    case bipBip = 0x3
    case beep = 0x4
    case beepBeepBeep = 0x5
    case beeeeeep = 0x6
    case bipBipBipbipBipBip = 0x7
    case beeepBeeep = 0x8
    // values greater than 0x8 for $19 and $1F commands can fault pod!
}

// BeepConfigType is used for the $1E Beep Config Command.
// Values 1 thru 8 are exactly the same as in BeepType above
// N.B. for BeepConfigType, noBeep is 0xF, while for BeepType it is 0x0
public enum BeepConfigType: UInt8 {
     // 0 always returns an error response for Beep Config
    case beepBeepBeepBeep = 0x1
    case bipBeepBipBeepBipBeepBipBeep = 0x2
    case bipBip = 0x3
    case beep = 0x4
    case beepBeepBeep = 0x5
    case beeeeeep = 0x6
    case bipBipBipbipBipBip = 0x7
    case beeepBeeep = 0x8
    // 0x9 and 0xA always return an error response for Beep Config
    case beepBeep = 0xB
    case beeep = 0xC
    case bipBeeeeep = 0xD
    case fiveSecondBeep = 0xE // can only be used if Pod is currently suspended!
    case noBeep = 0xF
}
