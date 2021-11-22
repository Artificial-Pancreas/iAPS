//
//  StatusMessage.swift
//  LibreTransmitterUI
//
//  Created by Bjørn Inge Berg on 23/05/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import SwiftUI

struct StatusMessage: Identifiable {
    var id: String { title }
    let title: String
    let message: String
}
