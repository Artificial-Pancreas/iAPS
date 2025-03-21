//
//  Image.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 02/03/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI

extension Image {
    init(danaImage: String) {
        self.init(uiImage: UIImage(named: danaImage, in: Bundle(for: DanaKitHUDProvider.self), compatibleWith: nil)!)
    }
}
