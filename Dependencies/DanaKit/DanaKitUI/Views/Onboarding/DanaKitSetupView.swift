//
//  DanaKitSetupView.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 26/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

typealias DebugFunction = () -> Void
struct DanaKitSetupView: View {
    @Environment(\.dismissAction) private var dismiss
    
    let nextAction: (Int) -> Void
    let debugAction: DebugFunction?
    
    @State var value: Int = 2
    private var currentValue: Binding<Int> {
        Binding(
            get: { value },
            set: { newValue in
                self.value = newValue
            }
       )
    }
    
    private let allowedOptions: [Int] = [1, 2]
    
    var body: some View {
        VStack(alignment: .leading) {
            title
                .onLongPressGesture(minimumDuration: 2) {
                    didLongPressOnTitle()
                }
            
            VStack(alignment: .leading) {
                Spacer()
                
                ResizeablePicker(selection: currentValue,
                                 data: self.allowedOptions,
                                 formatter: { formatter($0) })
                
                Spacer()
            }
            .padding(.horizontal)
            
            ContinueButton(action: { nextAction(value) })
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                    self.dismiss()
                })
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        Text(LocalizedString("Dana-i/RS Setup", comment: "Title for DanaKitSetupView"))
            .font(.largeTitle)
            .bold()
            .padding(.horizontal)
        Text(LocalizedString("Select your pump", comment: "Subtitle for DanaKitSetupView"))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
        
        Divider()
    }
    
    private func formatter(_ index: Int) -> String {
        switch (index) {
        case 0:
            // UNSUPPORTED ATM
            return LocalizedString("DanaRS-v1", comment: "danaRS v1 option text for DanaKitSetupView")
        case 1:
            return LocalizedString("DanaRS-v3", comment: "danaRS v3 option text for DanaKitSetupView")
        case 2:
            return LocalizedString("Dana-i", comment: "dana-i option text for DanaKitSetupView")
        default:
            return ""
        }
    }
    
    private func didLongPressOnTitle() {
        self.debugAction?()
    }
}

#Preview {
    DanaKitSetupView(nextAction: { _ in }, debugAction: nil)
}
