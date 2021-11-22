//
//  MessagePassing.swift
//  LibreTransmitter
//
//  Created by Bjørn Inge Berg on 21/04/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//

import Foundation

public func bundleSeedID() -> String? {
    let queryLoad: [String: AnyObject] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: "bundleSeedID" as AnyObject,
        kSecAttrService as String: "" as AnyObject,
        kSecReturnAttributes as String: kCFBooleanTrue
    ]

    var result: AnyObject?
    var status = withUnsafeMutablePointer(to: &result) {
        SecItemCopyMatching(queryLoad as CFDictionary, UnsafeMutablePointer($0))
    }

    if status == errSecItemNotFound {
        status = withUnsafeMutablePointer(to: &result) {
            SecItemAdd(queryLoad as CFDictionary, UnsafeMutablePointer($0))
        }
    }

    if status == noErr {
        if let resultDict = result as? [String: Any], let accessGroup = resultDict[kSecAttrAccessGroup as String] as? String {
            let components = accessGroup.components(separatedBy: ".")
            return components.first
        } else {
            return nil
        }
    } else {
        print("Error getting bundleSeedID to Keychain")
        return nil
    }
}

public func getDynamicAppGroupForMessagePassing() -> String? {
    if let seed = bundleSeedID() {
        return "group.com.\(seed).Loopkit.Loop.MessagePassing"
    }
    return nil
}
