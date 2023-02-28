//
//  Image.swift
//  CGMBLEKitUI
//
//  Created by Pete Schwamb on 9/24/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

extension Image {
    init(frameworkImage name: String, decorative: Bool = false) {
        if decorative {
            self.init(decorative: name, bundle: FrameworkBundle.main)
        } else {
            self.init(name, bundle: FrameworkBundle.main)
        }
    }
}
