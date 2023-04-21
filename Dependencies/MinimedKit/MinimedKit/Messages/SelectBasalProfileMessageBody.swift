//
//  SelectBasalProfileMessageBody.swift
//  MinimedKit
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation

public class SelectBasalProfileMessageBody: CarelinkLongMessageBody {
    public convenience init(newProfile: BasalProfile) {
        self.init(rxData: Data([1, newProfile.rawValue]))!
    }
}
