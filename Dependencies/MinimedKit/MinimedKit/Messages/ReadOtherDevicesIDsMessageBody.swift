//
//  ReadOtherDevicesIDsMessageBody.swift
//  MinimedKit
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


public class ReadOtherDevicesIDsMessageBody: CarelinkLongMessageBody {

    public let ids: [Data]

    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }

        let count = Int(rxData[1])

        var ids: [Data] = []

        for index in stride(from: 0, to: count, by: 1) {
            let start = (index * 5 + 3)
            let end = start + 4

            ids.append(rxData.subdata(in: start..<end))
        }

        self.ids = ids

        super.init(rxData: rxData)
    }
}


// Body[1] is the count Body[3..<7] is the first ID.
// 1f0101 a2105728 00 00000636 036f0040600107062f1dfc004020c107062f0e77000000000000000000000000000000000000000000000000000000000000000000
// 1f0201 a2105728 00 a2016016 036f0040600107062f1dfc004020c107062f0e77000000000000000000000000000000000000000000000000000000000000000000
