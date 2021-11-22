//
//  HashableClass.swift
//  LibreTransmitterUI
//
//  Created by Bjørn Inge Berg on 17/05/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

extension Hashable where Self: AnyObject {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension Equatable where Self: AnyObject {

    public static func == (lhs:Self, rhs:Self) -> Bool {
        return lhs === rhs
    }
}
