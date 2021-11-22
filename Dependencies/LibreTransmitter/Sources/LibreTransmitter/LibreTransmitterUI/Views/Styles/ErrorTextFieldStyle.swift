//
//  ErrorTextFieldStyle.swift
//  LibreTransmitterUI
//
//  Created by Bjørn Inge Berg on 28/04/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import SwiftUI

private struct ErrorTextFieldStyle : TextFieldStyle {
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.red,  lineWidth: 3))
    }
}
