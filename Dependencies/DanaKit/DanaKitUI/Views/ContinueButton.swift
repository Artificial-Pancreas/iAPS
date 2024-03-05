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
    let action: () -> Void
    var text = LocalizedString("Continue", comment: "Text for continue button")
    var loading: Binding<Bool> = .constant(false)
    
    init(loading: Binding<Bool>, text: String, action: @escaping () -> Void) {
        self.loading = loading
        self.text = text
        self.action = action
    }
    
    init(loading: Binding<Bool>, action: @escaping () -> Void) {
        self.loading = loading
        self.action = action
    }
    
    init(text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }
    
    init(action: @escaping () -> Void) {
        self.action = action
    }
    
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
            .disabled(loading.wrappedValue)
        }
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground)
            .shadow(radius: 5))
    }
}

#Preview {
    ContinueButton(action: {})
}
