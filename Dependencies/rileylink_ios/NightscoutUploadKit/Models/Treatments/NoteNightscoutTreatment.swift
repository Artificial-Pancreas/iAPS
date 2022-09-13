//
//  NoteNightscoutTreatment.swift
//  RileyLink
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation


public class NoteNightscoutTreatment: NightscoutTreatment {

    public init(timestamp: Date, enteredBy: String, notes: String? = nil, id: String? = nil) {
        super.init(timestamp: timestamp, enteredBy: enteredBy, notes: notes, id: id, eventType: .note)
    }

    required public init?(_ entry: [String : Any]) {
        super.init(entry)
    }
}
