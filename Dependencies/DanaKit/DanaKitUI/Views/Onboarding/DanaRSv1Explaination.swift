//
//  DanaRSv1Explaination.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 02/03/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct DanaRSv1Explaination: View {
    @Environment(\.dismissAction) private var dismiss
    
    let nextAction: () -> Void
    
    var body: some View {
        VStack {
            title
            
            ScrollView {
                VStack(alignment: .leading) {
                    Text(LocalizedString("Before starting with the pairing process, it is recommended to check, and if needed update, the pump password. You can do this by going to the pump settings -> user settings -> password. The default password is 1234, if this is your password, please consider changing it", comment: "check password text for danars v1"))
                        .padding(.bottom)
                    
                    Text(LocalizedString("After setting up the insulin type and bolus speed, you will see all the found Dana pumps. Select the pump you want to link with Loop.", comment: "General subtext for dana"))
                    
                    HStack {
                        Spacer()
                        Image(danaImage: "pairing_request")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    
                    Text(LocalizedString("During the pairing process, your DanaRS v3 will show a pairing prompt while you iPhone will show a prompt for a pairing code. On your pump, select OK and type the code on your iPhone. After that, Loop is ready to communicate with your DanaRS v1", comment: "Subtext for danars v1"))
                    
                    Spacer()
                }
                .padding(.horizontal)
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
        Text(LocalizedString("Setting up your DanaRS v1", comment: "Title for danars v1 explaination"))
            .font(.title)
            .bold()
        Divider()
            .padding(.vertical)
    }
}

#Preview {
    DanaRSv1Explaination(nextAction: {})
}
