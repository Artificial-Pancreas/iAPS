//
//  ContinueButton.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 03/03/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import LoopKitUI
import SwiftUI

struct ContinueButton: View {
    var text = LocalizedString("Continue", comment: "Text for continue button")
    var loading: Binding<Bool> = .constant(false)
    var disabled: Binding<Bool> = .constant(false)
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                if loading.wrappedValue {
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                } else {
                    Text(text)
                }
            }
            .buttonStyle(ActionButtonStyle())
            .padding([.bottom, .horizontal])
            .disabled(loading.wrappedValue || disabled.wrappedValue)
        }
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground)
            .shadow(radius: 5))
    }
}

#Preview {
    ContinueButton(action: {})
}
