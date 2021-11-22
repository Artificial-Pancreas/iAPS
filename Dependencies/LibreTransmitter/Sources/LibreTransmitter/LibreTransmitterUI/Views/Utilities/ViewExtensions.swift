//
//  ViewExtensions.swift
//  LibreTransmitterUI
//
//  Created by Bjørn Inge Berg on 03/07/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import SwiftUI

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
