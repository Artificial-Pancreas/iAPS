//
//  EnumeratedForEach.swift
//  LibreTransmitterUI
//
//  Created by Bjørn Inge Berg on 17/05/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import SwiftUI

struct EnumeratedForEach<ItemType, ContentView: View>: View {
    let data: [ItemType]
    let content: (Int, ItemType) -> ContentView

    init(_ data: [ItemType], @ViewBuilder content: @escaping (Int, ItemType) -> ContentView) {
        self.data = data
        self.content = content
    }

    var body: some View {
        ForEach(Array(self.data.enumerated()), id: \.offset) { idx, item in
            self.content(idx, item)
        }
    }
}
