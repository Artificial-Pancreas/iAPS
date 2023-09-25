//
//  TestUtilities.swift
//  OmniBLE
//
//  Created by Bill Gestrich on 12/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

extension String {
    //From start to, but not including, toIndex
    func substring(startIndex _startIndexInt: Int, toIndex _toIndexInt: Int) -> String? {
        assert(_startIndexInt < _toIndexInt)
        let startIndex = index(self.startIndex, offsetBy: _startIndexInt)
        let endIndex = index(self.startIndex, offsetBy: _toIndexInt - 1)
        return String(self[startIndex...endIndex])
    }
}
