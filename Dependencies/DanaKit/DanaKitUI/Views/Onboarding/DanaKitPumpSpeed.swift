//
//  DanaKitPumpSpeed.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 06/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct DanaKitPumpSpeed: View {
    @Environment(\.dismissAction) private var dismiss
    
    let speedsAllowed = BolusSpeed.all()
    @State var speedDefault = Int(BolusSpeed.speed12.rawValue)
    
    var next: ((BolusSpeed) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading) {
            title
            content
        }
        .padding(.horizontal)
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
    private var content: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(LocalizedString("The Dana pumps support different delivery speeds. You can set it up here, but also in the settings menu", comment: "Dana delivery speed body")).fixedSize(horizontal: false, vertical: true)
            Divider()
            ResizeablePicker(selection: $speedDefault,
                                     data: self.speedsAllowed,
                             formatter: { BolusSpeed.init(rawValue: UInt8($0))!.format() })
            Spacer()
            VStack {
                Button(action: {
                    guard let speed = BolusSpeed(rawValue: UInt8($speedDefault.wrappedValue)) else {
                        return
                    }
                    
                    next?(speed)
                }) {
                    Text(LocalizedString("Continue", comment: "Text for continue button"))
                        .actionButtonStyle(.primary)
                }
            }
            .padding()
        }
        .padding(.vertical, 8)
        
    }
    
    @ViewBuilder
    private var title: some View {
        Text(LocalizedString("Delivery speed", comment: "Title for delivery speed"))
            .font(.title)
            .bold()
    }
}

#Preview {
    DanaKitPumpSpeed()
}
