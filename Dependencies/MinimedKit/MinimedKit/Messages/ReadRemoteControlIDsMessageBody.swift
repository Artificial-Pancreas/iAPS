//
//  ReadRemoteControlIDsMessageBody.swift
//  MinimedKit
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

private let idSize = 6

public class ReadRemoteControlIDsMessageBody: CarelinkLongMessageBody {
    public let ids: [Data]

    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }

        var ids: [Data] = []

        remotes: for index in stride(from: 0, to: 3, by: 1) {
            let start = (index * idSize + 1)
            let end = start + idSize

            var remoteID = Data(capacity: idSize)

            for byte in rxData[start..<end] {
                let isEnabled = (byte & 0b00010000) == 0b00010000
                guard isEnabled else {
                    continue remotes
                }

                remoteID.append(byte & 0xf)
            }

            ids.append(remoteID)
        }

        self.ids = ids

        super.init(rxData: rxData)
    }
}
