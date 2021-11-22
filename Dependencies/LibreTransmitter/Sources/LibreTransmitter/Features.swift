//
//  Features.swift
//  LibreTransmitter
//
//  Created by Bjørn Inge Berg on 30/08/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import Foundation

#if canImport(CoreNFC)
import CoreNFC
#endif

public final class Features{

    static public var logSubsystem = "no.bjorninge.libre"

    static var phoneNFCAvailable: Bool {
        #if canImport(CoreNFC)
        if NSClassFromString("NFCNDEFReaderSession") == nil {
            return false
            
        }

        return NFCNDEFReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    static var supportsLogExport: Bool {
        if #available(iOS 15, *) {
            return true
        }
        return false
    }




}

