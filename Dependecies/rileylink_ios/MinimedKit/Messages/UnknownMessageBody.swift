//
//  UnknownMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/16/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public struct UnknownMessageBody: MessageBody, DictionaryRepresentable {
    public static var length = 0

    let rxData: Data

    public init?(rxData: Data) {
        self.rxData = rxData
    }

    public var txData: Data {
        return rxData
    }

    public var dictionaryRepresentation: [String: Any] {
        return ["rawData": rxData]
    }
}
