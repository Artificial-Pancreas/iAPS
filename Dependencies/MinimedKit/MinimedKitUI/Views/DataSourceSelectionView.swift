//
//  DataSourceSelectionView.swift
//  MinimedKitUI
//
//  Created by Pete Schwamb on 11/30/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI
import MinimedKit
import LoopKitUI

struct DataSourceSelectionView: View {

    @Binding var batteryType: InsulinDataSource

    var body: some View {
        VStack {
            List {
                Picker("Preferred Data Source", selection: $batteryType) {
                    ForEach(InsulinDataSource.allCases, id: \.self) { dataSource in
                        Text(dataSource.description)
                    }
                }
                .pickerStyle(.inline)
                Section(content: {
                }, footer: {
                    Text(LocalizedString("Insulin delivery can be determined from the pump by either interpreting the event history or comparing the reservoir volume over time. Reading event history allows for a more accurate status graph and uploading up-to-date treatment data to Nightscout, at the cost of faster pump battery drain and the possibility of a higher radio error rate compared to reading only reservoir volume. If the selected source cannot be used for any reason, the system will attempt to fall back to the other option.", comment: "Instructions on selecting an insulin data source"))
                })
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(LocalizedString("Preferred Data Source", comment: "navigation title for pump battery type selection"))
    }
}
