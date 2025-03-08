//
//  IdentifiableClass.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 18/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
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
