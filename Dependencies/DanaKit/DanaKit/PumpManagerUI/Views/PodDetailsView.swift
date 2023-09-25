//
//  PodDetailsView.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 4/14/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

public struct PodDetails {
    var lotNumber: UInt32
    var sequenceNumber: UInt32
    var firmwareVersion: String
    var bleFirmwareVersion: String
    var deviceName: String?
    var totalDelivery: Double?
    var lastStatus: Date?
    var fault: FaultEventCode?
    var activatedAt: Date?
    var activeTime: TimeInterval?
    var pdmRef: String?
}

struct PodDetailsView: View {
    @Environment(\.guidanceColors) var guidanceColors
    
    var podDetails: PodDetails
    var title: String
    
    let statusAgeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .short

        return formatter
    }()

    let activeTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .full

        return formatter
    }()

    let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .medium
        dateFormatter.doesRelativeDateFormatting = true
        return dateFormatter
    }()

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
    
    var totalDeliveryText: String {
        if let delivery = podDetails.totalDelivery {
            return String(format: LocalizedString("%g U", comment: "Format string for total delivery on pod details screen"), delivery)
        } else {
            return LocalizedString("NA", comment: "String shown on pod details for total delivery when not available.")
        }
    }

    func activeTimeText(_ duration: TimeInterval) -> String {
        return activeTimeFormatter.string(from: duration) ?? LocalizedString("NA", comment: "String shown on pod details for active time when conversion fails.")
    }
    
    var lastStatusText: String {
        if let lastStatus = podDetails.lastStatus, let ageString = statusAgeFormatter.string(from: Date().timeIntervalSince(lastStatus)) {
            return String(format: LocalizedString("%@ ago", comment: "Format string for last status date on pod details screen"), ageString)
        } else {
            return LocalizedString("NA", comment: "String shown on pod details for last status date when not available.")
        }
    }
    
    var body: some View {
        List {
            if let deviceName = podDetails.deviceName {
                row(LocalizedString("Device Name", comment: "description label for device name pod details row"), value: deviceName)
            }
            row(LocalizedString("Lot Number", comment: "description label for lot number pod details row"), value: String(describing: podDetails.lotNumber))
            row(LocalizedString("Sequence Number", comment: "description label for sequence number pod details row"), value: String(describing: podDetails.sequenceNumber))
            row(LocalizedString("Firmware Version", comment: "description label for firmware version pod details row"), value: podDetails.firmwareVersion)
            row(LocalizedString("BLE Firmware Version", comment: "description label for ble firmware version pod details row"), value: podDetails.bleFirmwareVersion)
            row(LocalizedString("Total Delivery", comment: "description label for total delivery pod details row"), value: totalDeliveryText)
            if let activeTime = podDetails.activeTime, let activatedAt = podDetails.activatedAt {
                row(LocalizedString("Pod Activated", comment: "description label for activated at timne pod details row"), value: dateFormatter.string(from: activatedAt))
                row(LocalizedString("Active Time", comment: "description label for active time pod details row"), value: activeTimeText(activeTime))
            } else {
                row(LocalizedString("Last Status", comment: "description label for last status date pod details row"), value: lastStatusText)
            }
            if let fault = podDetails.fault, let pdmRef = podDetails.pdmRef {
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(guidanceColors.critical)
                            Text(LocalizedString("Pod Fault Details", comment: "description label for pod fault details"))
                                .fontWeight(.semibold)
                        }.padding(.vertical, 4)
                        Text(String(describing: fault))
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.secondary)
                        Text("Ref: " + pdmRef)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationBarTitle(Text(title), displayMode: .automatic)
    }
}

struct PodDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        PodDetailsView(podDetails: PodDetails(lotNumber: 0x1234, sequenceNumber: 0x1234, firmwareVersion: "1.1.1", bleFirmwareVersion: "2.2.2", deviceName: "PreviewPod", totalDelivery: 10, lastStatus: Date(), fault: FaultEventCode(rawValue: 0x67), activatedAt: Date().addingTimeInterval(.days(1))), title: "Device Details")
    }
}
