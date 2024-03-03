//
//  DanaRSvv1Password.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 03/03/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKitUI
import Combine

struct DanaRSvv1Password: View {
    @Environment(\.dismissAction) private var dismiss
    
    @State var password: UInt16?
    
    let nextAction: (UInt16) -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            title
            TextField(LocalizedString("Fill in password", comment: "password placeholder danars v1"), value: $password, format: .number)
                .keyboardType(.numberPad)
                .padding(.horizontal)
            Spacer()
            
            VStack(spacing: 0) {
                Button(LocalizedString("Continue", comment: "Text for continue button"), action: { nextAction(password ?? 0) })
                    .buttonStyle(ActionButtonStyle())
                    .disabled(password == nil)
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
        Text(LocalizedString("Password DanaRS v1", comment: "Title for danars v1 password"))
            .font(.title)
            .bold()
        Divider()
            .padding(.vertical)
    }
}

#Preview {
    DanaRSvv1Password(nextAction: { _ in })
}
