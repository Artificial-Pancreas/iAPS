//
//  InsertCannulaView.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 2/5/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct InsertCannulaView: View {
    
    @ObservedObject var viewModel: InsertCannulaViewModel
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    @State private var cancelModalIsPresented: Bool = false
    
    var body: some View {
        GuidePage(content: {
            VStack {
                LeadingImage("Pod")

                HStack {
                    InstructionList(instructions: [
                        LocalizedString("Tap below to start cannula insertion.", comment: "Label text for step one of insert cannula instructions"),
                        LocalizedString("Wait until insertion is completed.", comment: "Label text for step two of insert cannula instructions"),
                    ])
                    .disabled(viewModel.state.instructionsDisabled)

                }
                .padding(.bottom, 8)
            }
            .accessibility(sortPriority: 1)
        }) {
            VStack {
                if self.viewModel.state.showProgressDetail {
                    self.viewModel.error.map {
                        ErrorView($0, errorClass: $0.recoverable ? .normal : .critical)
                            .accessibility(sortPriority: 0)
                    }

                    if self.viewModel.error == nil {
                        VStack {
                            ProgressIndicatorView(state: self.viewModel.state.progressState)
                            if self.viewModel.state.isFinished {
                                FrameworkLocalText("Inserted", comment: "Label text indicating insertion finished.")
                                    .bold()
                                    .padding(.top)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
                if self.viewModel.error != nil {
                    Button(action: {
                        self.viewModel.didRequestDeactivation?()
                    }) {
                        Text(LocalizedString("Deactivate Pod", comment: "Button text for deactivate pod button"))
                            .accessibility(identifier: "button_deactivate_pod")
                            .actionButtonStyle(.secondary)
                    }
                    .disabled(self.viewModel.state.isProcessing)
                }
                
                if (self.viewModel.error == nil || self.viewModel.error?.recoverable == true) {
                    Button(action: {
                        self.viewModel.continueButtonTapped()
                    }) {
                        Text(self.viewModel.state.nextActionButtonDescription)
                            .accessibility(identifier: "button_next_action")
                            .accessibility(label: Text(self.viewModel.state.actionButtonAccessibilityLabel))
                            .actionButtonStyle(.primary)
                    }
                    .disabled(self.viewModel.state.isProcessing)
                    .animation(nil)
                    .zIndex(1)
                }
            }
            .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
            .padding()
        }
        .animation(.default)
        .alert(isPresented: $cancelModalIsPresented) { cancelPairingModal }
        .navigationBarTitle(LocalizedString("Insert Cannula", comment: "navigation bar title for insert cannula"), displayMode: .automatic)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(trailing: cancelButton)
    }
    
    var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button text in navigation bar on insert cannula screen")) {
            cancelModalIsPresented = true
        }
        .accessibility(identifier: "button_cancel")
    }
    
    var cancelPairingModal: Alert {
        return Alert(
            title: FrameworkLocalText("Are you sure you want to cancel Pod setup?", comment: "Alert title for cancel pairing modal"),
            message: FrameworkLocalText("If you cancel Pod setup, the current Pod will be deactivated and will be unusable.", comment: "Alert message body for confirm pod attachment"),
            primaryButton: .destructive(FrameworkLocalText("Yes, Deactivate Pod", comment: "Button title for confirm deactivation option"), action: { viewModel.didRequestDeactivation?() } ),
            secondaryButton: .default(FrameworkLocalText("No, Continue With Pod", comment: "Continue pairing button title of in pairing cancel modal"))
        )
    }

}
