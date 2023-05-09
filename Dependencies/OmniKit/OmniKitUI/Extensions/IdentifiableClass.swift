//
//  IdentifiableClass.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 3/19/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

protocol IdentifiableClass: AnyObject {
    static var className: String { get }
}


extension IdentifiableClass {
    static var className: String {
        return NSStringFromClass(self).components(separatedBy: ".").last!
    }
}
