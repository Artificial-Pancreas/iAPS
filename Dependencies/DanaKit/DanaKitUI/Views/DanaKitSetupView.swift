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
    
    let nextAction: () -> Void
    let debugAction: DebugFunction?
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading) {
                close
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        title
                            .padding(.top, 5)
                            .onLongPressGesture(minimumDuration: 2) {
                                didLongPressOnTitle()
                            }
                        Divider()
                        bodyText
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                }
            }
            .padding(.horizontal)
            Spacer()
            VStack(spacing: 0) {
                continueButton
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
    
    @ViewBuilder
    private var bodyText: some View {
        Text(LocalizedString("You will now begin the process by connecting to your Dana-i/RS pump. After that, one of the three things can happen:", comment: "bodyText for DanaKitSetupView"))
        Text(LocalizedString("- For DanaRS-v1, Unsupported (yet)", comment: "danaRS v1 option text for DanaKitSetupView"))
        Text(LocalizedString("- For DanaRS-v3, type 2 sequences of numbers and letters displayed on the pump to pair and the setup is completed!", comment: "danaRS v3 option text for DanaKitSetupView"))
        Text(LocalizedString("- For Dana-i, the standard Bluetooth pairing pin dialog will appear. You have to enter a 6-digit number password, displayed on the pump, and the setup is completed!", comment: "dana-i option text for DanaKitSetupView"))
            .padding(.top, 10)
    }
    
    @ViewBuilder
    private var close: some View {
        HStack {
            Spacer()
            cancelButton
        }
        .padding(.top)
    }
    
    private var continueButton: some View {
        Button(LocalizedString("Continue", comment: "Text for continue button on PodSetupView"), action: nextAction)
            .buttonStyle(ActionButtonStyle())
    }
    
    private var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
            self.dismiss()
        })
    }
    
    private func didLongPressOnTitle() {
        self.debugAction?()
    }
}

#Preview {
    DanaKitSetupView(nextAction: {}, debugAction: nil)
}
