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
    
    private let allowedOptions: [Int] = [0, 1, 2]
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading) {
                close
                title
                    .padding(.all)
                    .onLongPressGesture(minimumDuration: 2) {
                        didLongPressOnTitle()
                    }
                Divider()
                
                VStack(alignment: .center, spacing: 2) {
                    Spacer()
                    
                    Text(LocalizedString("Select your pump", comment: "Subtitle for DanaKitSetupView"))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    ResizeablePicker(selection: currentValue,
                                     data: self.allowedOptions,
                                     formatter: { formatter($0) })
                    
                    Spacer()
                }
            }
            .padding(.horizontal)
            VStack(spacing: 0) {
                Button(LocalizedString("Continue", comment: "Text for continue button"), action: { nextAction(value) })
                    .buttonStyle(ActionButtonStyle())
                    .padding([.bottom, .horizontal])
            }
                .padding(.top, 10)
                .background(Color(.secondarySystemGroupedBackground)
                .shadow(radius: 5))
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private var title: some View {
        Text(LocalizedString("Dana-i/RS Setup", comment: "Title for DanaKitSetupView"))
            .font(.largeTitle)
            .bold()
            .padding(.vertical)
    }
    
    private func formatter(_ index: Int) -> String {
        switch (index) {
        case 0:
            return LocalizedString("DanaRS-v1", comment: "danaRS v1 option text for DanaKitSetupView")
        case 1:
            return LocalizedString("DanaRS-v3", comment: "danaRS v3 option text for DanaKitSetupView")
        case 2:
            return LocalizedString("Dana-i", comment: "dana-i option text for DanaKitSetupView")
        default:
            return ""
        }
    }
    
    @ViewBuilder
    private var close: some View {
        HStack {
            Spacer()
            Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                self.dismiss()
            })
        }
        .padding(.top)
    }
    
    private func didLongPressOnTitle() {
        self.debugAction?()
    }
}

#Preview {
    DanaKitSetupView(nextAction: { _ in }, debugAction: nil)
}
