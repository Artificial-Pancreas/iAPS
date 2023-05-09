//
//  PacketType.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/2/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

public enum PacketType: UInt8 {
    case mySentry  = 0xA2
    case meter     = 0xA5
    case carelink  = 0xA7
    case sensor    = 0xA8
}
