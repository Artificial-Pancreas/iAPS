//
//  InsulinTypeConfirmation.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 28/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct InsulinTypeConfirmation: View {
    @Environment(\.dismissAction) private var dismiss
    
    @State private var insulinType: InsulinType?
    private var supportedInsulinTypes: [InsulinType]
    private var didConfirm: (InsulinType) -> Void
    
    init(initialValue: InsulinType, supportedInsulinTypes: [InsulinType], didConfirm: @escaping (InsulinType) -> Void) {
        self._insulinType = State(initialValue: initialValue)
        self.supportedInsulinTypes = supportedInsulinTypes
        self.didConfirm = didConfirm
    }
    
    func continueWithType(_ insulinType: InsulinType?) {
        if let insulinType = insulinType {
            didConfirm(insulinType)
        } else {
            assertionFailure()
        }
    }
    
    var body: some View {
        VStack {
            List {
                Section {
                    Text(LocalizedString("Select the type of insulin that you will be using in this pump.", comment: "Title text for insulin type confirmation page"))
                }
                Section {
                    InsulinTypeChooser(insulinType: $insulinType, supportedInsulinTypes: supportedInsulinTypes)
                }
                .buttonStyle(PlainButtonStyle()) // Disable row highlighting on selection
            }
            .insetGroupedListStyle()
            
            Button(action: { self.continueWithType(insulinType) }) {
                Text(LocalizedString("Continue", comment: "Text for continue button"))
                    .actionButtonStyle(.primary)
                    .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                    self.dismiss()
                })
            }
        }
    }
}

struct InsulinTypeConfirmation_Previews: PreviewProvider {
    static var previews: some View {
        InsulinTypeConfirmation(initialValue: .novolog, supportedInsulinTypes: InsulinType.allCases, didConfirm: { (newType) in })
    }
}
