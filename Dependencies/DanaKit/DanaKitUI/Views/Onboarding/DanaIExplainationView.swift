//
//  DanaIExplaination.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 02/03/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct DanaIExplainationView: View {
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
                    
                    Text(LocalizedString("During the pairing process, your Dana-i will show a pairing prompt while your iPhone will show a prompt for a pairing code. On you pump, select OK and type the 6-digit code in screen on your iPhone. After that, Loop is ready to communicate with your Dana-i", comment: "Subtext for dana-i"))
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
        Text(LocalizedString("Setting up your Dana-i", comment: "Title for dana-i explaination"))
            .font(.title)
            .bold()
        Divider()
            .padding(.vertical)
    }
}

#Preview {
    DanaIExplainationView(nextAction: {})
}
