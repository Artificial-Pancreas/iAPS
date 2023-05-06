//
//  NibLoadable.swift
//  MinimedKitUI
//
//  Created by Pete Schwamb on 3/19/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import UIKit

protocol NibLoadable: IdentifiableClass {
    static func nib() -> UINib
}


extension NibLoadable {
    static func nib() -> UINib {
        return UINib(nibName: className, bundle: Bundle(for: self))
    }
}
