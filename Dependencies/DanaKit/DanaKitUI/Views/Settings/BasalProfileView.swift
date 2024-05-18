//
//  BasalProfileView.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 05/03/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct BasalProfileView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    
    private var currentValue: Binding<Int> {
        Binding(
            get: { Int(viewModel.basalProfileNumber) },
            set: { newValue in
                viewModel.basalProfileNumber = UInt8(newValue)
            }
       )
    }
    
    let allowedOptions = Array(0..<4)
    @ObservedObject var viewModel: BasalProfileViewModel
    
    
    var body: some View {
        VStack(alignment: .leading) {
            titleView
            
            VStack(alignment: .leading) {
                Spacer()
                
                ResizeablePicker(selection: currentValue,
                                 data: self.allowedOptions,
                                 formatter: { formatter($0) })
                    .padding(.horizontal)
                
                Spacer()
                
                
            }
            .padding(.horizontal)
            
            ContinueButton(loading: $viewModel.loading, action: {
                viewModel.basalProfileNumberChanged() {
                    // Go back action
                    presentationMode.wrappedValue.dismiss()
                }
            })
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
    }
    
    @ViewBuilder
    private var titleView: some View {
        Text(LocalizedString("Basal profile", comment: "Text for Basal profile"))
            .font(.title)
            .bold()
            .padding(.horizontal)
        
        Text(LocalizedString("Set the basal profile the pump should use. Note, that it will overwrite the profile that is in the pump, with the one in Loop", comment: "Description for basal profile number"))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
        
        Divider()
    }
    
    private func didChange() {
        
    }
    
    private func formatter(_ index: Int) -> String {
        if index == 0 {
            return "A"
        } else if index == 1 {
            return "B"
        } else if index == 2 {
            return "C"
        } else {
            return "D"
        }
    }
}

#Preview {
    BasalProfileView(viewModel: BasalProfileViewModel(nil))
}
