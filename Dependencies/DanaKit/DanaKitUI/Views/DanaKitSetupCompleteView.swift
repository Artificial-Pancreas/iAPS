//
//  DanaKitSetupCompleteView.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 06/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct DanaKitSetupCompleteView: View {
    var finish: (() -> Void)?
    var friendlyPumpModelName: String
    var imageName: String
    
    var body: some View {
        VStack(alignment: .leading) {
            title
            content
        }
        .padding(.horizontal)
        .navigationBarHidden(false)
    }
    
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Spacer()
                Image(uiImage: UIImage(named: imageName, in: Bundle(for: DanaKitHUDProvider.self), compatibleWith: nil)!)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                Spacer()
            }
            Text(LocalizedString("Your ", comment: "Dana setup complete p1") + friendlyPumpModelName + LocalizedString(" is ready to be used!", comment: "Dana setup complete p2"))
        }
        VStack(alignment: .leading) {
            Text(LocalizedString("Note: You Dana pump has a special setting which allows you to silence your Dana pump beeps. To enable this, please contact your Dana distributor", comment: "Dana setup SMB setting"))
        }
        Spacer()
        Button(action: {
            finish?()
        }) {
            Text(LocalizedString("Finish", comment: "Text for finish button"))
                .actionButtonStyle(.primary)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }
    
    @ViewBuilder
    private var title: some View {
        Text(LocalizedString("Setup Complete", comment: "Title for setup complete"))
            .font(.title)
            .bold()
    }
}

#Preview {
    DanaKitSetupCompleteView(finish: {}, friendlyPumpModelName: "Dana-i", imageName: "danai")
}
