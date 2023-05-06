//
//  PartialDecode.swift
//  RileyLink
//
//  Created by Pete Schwamb on 5/11/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation


public enum PartialDecode<T1, T2> {
    case known(T1)
    case unknown(T2)
}
