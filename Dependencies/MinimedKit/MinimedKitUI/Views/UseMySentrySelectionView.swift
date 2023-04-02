//
//  UseMySentrySelectionView.swift
//  MinimedKitUI
//
//  Created by Pete Schwamb on 11/30/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI
import MinimedKit
import LoopKitUI

struct UseMySentrySelectionView: View {

    @Binding var mySentryConfig: MySentryConfig

    var body: some View {
        VStack {
            List {
                Picker("Use MySentry", selection: $mySentryConfig) {
                    ForEach(MySentryConfig.allCases, id: \.self) { config in
                        Text(config.localizedDescription)
                    }
                }
                .pickerStyle(.inline)
                Section(content: {}, footer: {
                    Text(LocalizedString("Medtronic pump models 523, 723, 554, and 754 have a feature called 'MySentry' that periodically broadcasts the reservoir and pump battery levels.  Listening for these broadcasts allows Loop to communicate with the pump less frequently, which can increase pump battery life.  However, when using this feature the RileyLink stays awake more of the time and uses more of its own battery.  Enabling this may lengthen pump battery life, while disabling it may lengthen RileyLink battery life. This setting is ignored for other pump models.", comment: "Instructions on selecting setting for MySentry"))
                })
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(LocalizedString("Use MySentry", comment: "navigation title for pump battery type selection"))
    }
}
