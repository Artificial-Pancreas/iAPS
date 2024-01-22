//
//  DanaKitSettingsPumpSpeed.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 17/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct DanaKitSettingsPumpSpeed: View {
    let speedsAllowed = BolusSpeed.all()
    @State var currentSpeed: Int {
        didSet {
            didChange?(BolusSpeed.init(rawValue: UInt8(currentSpeed))!)
        }
    }
    
    var didChange: ((BolusSpeed) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading) {
            title
            content
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(LocalizedString("The Dana pumps support different delivery speeds. You can set it up here, but also in the settings menu", comment: "Dana delivery speed body")).fixedSize(horizontal: false, vertical: true)
            Divider()
            ResizeablePicker(selection: $currentSpeed,
                                     data: self.speedsAllowed,
                                     formatter: { BolusSpeed.init(rawValue: UInt8($0))!.format() })
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
    DanaKitSettingsPumpSpeed(currentSpeed: Int(BolusSpeed.speed12.rawValue))
}
