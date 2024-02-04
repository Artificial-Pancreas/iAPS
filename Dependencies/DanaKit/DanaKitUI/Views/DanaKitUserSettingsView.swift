//
//  DanaKitUserSettingsView.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 29/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct DanaKitUserSettingsView: View {
    @ObservedObject var viewModel: DanaKitUserSettingsViewModel
    
    private var revervoirWarningView: PickerView {
        PickerView(
            currentOption: Int(viewModel.lowReservoirRate),
            allowedOptions: Array(5...40),
            formatter: { value in String(value) + LocalizedString("U", comment: "Insulin unit")},
            didChange: { value in viewModel.lowReservoirRate = UInt8(value) },
            title: LocalizedString("Low reservoir reminder", comment: "Text for low reservoir reminder"),
            description: LocalizedString("The pump reminds you when the amount of insulin in the pump reaches this level", comment: "Description for low reservoir reminder")
        )
    }
    
    private var time24hView: PickerView {
        PickerView(
            currentOption: viewModel.isTimeDisplay24H ? 1 : 0,
            allowedOptions: [0, 1],
            formatter: { value in value == 1 ? LocalizedString("On", comment: "text on") : LocalizedString("Off", comment: "text off")},
            didChange: { value in viewModel.isTimeDisplay24H = value == 1 },
            title: LocalizedString("24h display", comment: "Text for 24h display"),
            description: LocalizedString("Should time be display in 12h or 24h", comment: "Description for 24h display")
        )
    }
    
    @ViewBuilder
    var body: some View {
        VStack {
            List {
                NavigationLink(destination: revervoirWarningView) {
                    HStack {
                        Text(LocalizedString("Low reservoir reminder", comment: "Text for low reservoir reminder"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(String(viewModel.lowReservoirRate) + LocalizedString("U", comment: "Insulin unit"))
                    }
                }
                NavigationLink(destination: time24hView) {
                    HStack {
                        Text(LocalizedString("24h display", comment: "Text for 24h display"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(viewModel.isTimeDisplay24H ? LocalizedString("On", comment: "text on") : LocalizedString("Off", comment: "text off"))
                    }
                }
            }
            Spacer()
            Button(action: { viewModel.storeUserOption() }) {
                Text(LocalizedString("Save", comment: "Text for save button"))
                    .actionButtonStyle(.primary)
                    .padding()
            }
            .disabled(viewModel.storingUseroption)
        }
        .navigationBarTitle(LocalizedString("User options", comment: "Title for user options"))
    }
}

#Preview {
    DanaKitUserSettingsView(viewModel: DanaKitUserSettingsViewModel(nil))
}
