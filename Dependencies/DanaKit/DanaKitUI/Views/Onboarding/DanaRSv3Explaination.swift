//
//  DanaRSv3Explaination.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 02/03/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct DanaRSv3Explaination: View {
    @Environment(\.dismissAction) private var dismiss
    
    let nextAction: () -> Void
    
    var body: some View {
        VStack {
            title
            
            ScrollView {
                VStack(alignment: .leading) {
                    Text(LocalizedString("After setting up the insulin type and bolus speed, you will see all the found Dana pumps. Select the pump you want to link with Loop.", comment: "General subtext for dana"))
                        .padding(.horizontal)
                    
                    HStack {
                        Spacer()
                        Image(danaImage: "pairing_request")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    
                    Text(LocalizedString("During the pairing process, your DanaRS v3 will show a pairing prompt while you iPhone will show a prompt for two pairing codes. On your pump, select OK and type the two codes on your iPhone. After that, Loop is ready to communicate with your DanaRS v3", comment: "Subtext for danars v3"))
                        .padding(.horizontal)
                    
                    Spacer()
                }
            }
            VStack(spacing: 0) {
                Button(LocalizedString("Continue", comment: "Text for continue button"), action: nextAction)
                    .buttonStyle(ActionButtonStyle())
                    .padding([.bottom, .horizontal])
            }
                .padding(.top, 10)
                .background(Color(.secondarySystemGroupedBackground)
                .shadow(radius: 5))
        }
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
        Text(LocalizedString("Setting up your DanaRS v3", comment: "Title for danars v3 explaination"))
            .font(.title)
            .bold()
        Divider()
            .padding(.vertical)
    }
}

#Preview {
    DanaRSv3Explaination(nextAction: {})
}
