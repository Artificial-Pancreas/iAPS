//
//  MessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/4/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public protocol MessageBody: CustomStringConvertible {
    static var length: Int {
        get
    }

    var txData: Data {
        get
    }
}

public protocol DecodableMessageBody: MessageBody {
    init?(rxData: Data)
}

public protocol DictionaryRepresentable {
    var dictionaryRepresentation: [String: Any] {
        get
    }
}
