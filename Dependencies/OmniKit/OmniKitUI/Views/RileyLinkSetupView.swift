//
//  RileyLinkSelectionView.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 6/7/22.
//  Copyright © 2022 Pete Schwamb. All rights reserved.
//

import SwiftUI
import LoopKitUI
import RileyLinkKitUI

struct RileyLinkSetupView: View {
    public var cancelButtonTapped: (() -> Void)?

    @Environment(\.dismissAction) private var dismiss

    let nextAction: () -> Void

    @ObservedObject private var dataSource: RileyLinkListDataSource

    init(dataSource: RileyLinkListDataSource, nextAction: @escaping () -> Void) {
        self.dataSource = dataSource
        self.nextAction = nextAction
    }

    @State private var isOn: Bool = false


    var body: some View {
        VStack {
            List {
                VStack {
                    Image("RileyLink", bundle: Bundle(for: RileyLinkCell.self))
                        .resizable()
                        .foregroundColor(Color(imageTint))
                        .aspectRatio(contentMode: ContentMode.fit)
                    bodyText
                        .foregroundColor(.secondary)
                }
                Section(header: HStack {
                    FrameworkLocalText("Devices", comment: "Header for devices section of RileyLinkSetupView")
                    Spacer()
                    ProgressView()
                }) {
                    ForEach(dataSource.devices, id: \.peripheralIdentifier) { device in
                        Toggle(isOn: dataSource.autoconnectBinding(for: device)) {
                            HStack {
                                Text(device.name ?? "Unknown")
                                Spacer()
                                Text(formatRSSI(rssi:device.rssi)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer()
            continueButton
                .padding([.bottom, .horizontal])

        }
        .navigationTitle(LocalizedString("RileyLink Setup", comment: "Navigation title for RileyLinkSetupView"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                    cancelButtonTapped?()
                })
            }
        }
        .navigationBarHidden(false)
        .onAppear { dataSource.isScanningEnabled = true }
        .onDisappear { dataSource.isScanningEnabled = false }
    }

    var decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    private func formatRSSI(rssi: Int?) -> String {
        if let rssi = rssi, let rssiStr = decimalFormatter.decibleString(from: rssi) {
            return rssiStr
        } else {
            return ""
        }
    }

    var imageTint: UIColor {
        return UIColor(named: "RileyLink Tint", in: Bundle(for: RileyLinkCell.self), compatibleWith: nil) ?? .gray
    }

    @ViewBuilder
    private var bodyText: some View {
        Text(LocalizedString("RileyLink allows for communication with the pump over Bluetooth", comment: "bodyText for RileyLinkSetupView"))
    }

    private var continueButton: some View {
        Button(LocalizedString("Continue", comment: "Text for continue button on PodSetupView"), action: nextAction)
            .buttonStyle(ActionButtonStyle())
            .disabled(!dataSource.connecting)

    }

}
