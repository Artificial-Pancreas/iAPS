//
//  ErrorResponse.swift
//  OmniKit
//
//  Created by Pete Schwamb on 2/25/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

fileprivate let errorResponseCode_badNonce: UInt8 = 0x14 // only returned on Eros

public enum ErrorResponseType {
    case badNonce(nonceResyncKey: UInt16) // only returned on Eros
    case nonretryableError(code: UInt8, faultEventCode: FaultEventCode, podProgress: PodProgressStatus)
}

// 06 14 WWWW, WWWW is the encoded nonce resync key
// 06 EE FF0P, EE != 0x14, FF = fault code (if any), 0P = pod progress status (1..15)

public struct ErrorResponse : MessageBlock {
    public let blockType: MessageBlockType = .errorResponse
    public let errorResponseType: ErrorResponseType
    public let data: Data

    public init(encodedData: Data) throws {
        let errorCode = encodedData[2]
        switch (errorCode) {
        case errorResponseCode_badNonce:
            // For this error code only the 2 next bytes are the encoded nonce resync key (only returned on Eros)
            let nonceResyncKey: UInt16 = encodedData[3...].toBigEndian(UInt16.self)
            errorResponseType = .badNonce(nonceResyncKey: nonceResyncKey)
            break
        default:
            // All other error codes are some non-retryable command error. In this case,
            // the next 2 bytes are any saved fault code (typically 0) and the pod progress value.
            let faultEventCode = FaultEventCode(rawValue: encodedData[3])
            guard let podProgress = PodProgressStatus(rawValue: encodedData[4]) else {
                throw MessageError.unknownValue(value: encodedData[4], typeDescription: "ErrorResponse PodProgressStatus")
            }
            errorResponseType = .nonretryableError(code: errorCode, faultEventCode: faultEventCode, podProgress: podProgress)
            break
        }
        self.data = encodedData
    }
}

