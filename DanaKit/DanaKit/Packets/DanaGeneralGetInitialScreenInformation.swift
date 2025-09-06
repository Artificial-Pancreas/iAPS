//
//  DanaGeneralGetInitialScreenInformation.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketGeneralGetInitialScreenInformation {
    let isPumpSuspended: Bool
    let isTempBasalInProgress: Bool
    let isExtendedInProgress: Bool
    let isDualBolusInProgress: Bool
    let dailyTotalUnits: Double
    let maxDailyTotalUnits: Double
    let reservoirRemainingUnits: Double
    let currentBasal: Double
    let tempBasalPercent: Double
    let batteryRemaining: Double
    let extendedBolusAbsoluteRemaining: Double
    let insulinOnBoard: Double
    let errorState: Int?
}

let CommandGeneralGetInitialScreenInformation: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_REVIEW__INITIAL_SCREEN_INFORMATION & 0xff)

func generatePacketGeneralGetInitialScreenInformation() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_REVIEW__INITIAL_SCREEN_INFORMATION, data: nil)
}

func parsePacketGeneralGetInitialScreenInformation(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketGeneralGetInitialScreenInformation> {
    if data.count < 17 {
        return DanaParsePacket(success: false, rawData: data, data: PacketGeneralGetInitialScreenInformation(
            isPumpSuspended: false,
            isTempBasalInProgress: false,
            isExtendedInProgress: false,
            isDualBolusInProgress: false,
            dailyTotalUnits: -1,
            maxDailyTotalUnits: -1,
            reservoirRemainingUnits: -1,
            currentBasal: -1,
            tempBasalPercent: -1,
            batteryRemaining: -1,
            extendedBolusAbsoluteRemaining: -1,
            insulinOnBoard: -1,
            errorState: nil
        ))
    }

    let statusPump = data[DataStart]

    return DanaParsePacket(success: true, rawData: data, data: PacketGeneralGetInitialScreenInformation(
        isPumpSuspended: (statusPump & 0x01) == 0x01,
        isTempBasalInProgress: (statusPump & 0x10) == 0x10,
        isExtendedInProgress: (statusPump & 0x04) == 0x04,
        isDualBolusInProgress: (statusPump & 0x08) == 0x08,
        dailyTotalUnits: Double(data.uint16(at: DataStart + 1)) / 100,
        maxDailyTotalUnits: Double(data.uint16(at: DataStart + 3)) / 100,
        reservoirRemainingUnits: Double(data.uint16(at: DataStart + 5)) / 100,
        currentBasal: Double(data.uint16(at: DataStart + 7)) / 100,
        tempBasalPercent: Double(data[DataStart + 9]),
        batteryRemaining: Double(data[DataStart + 10]),
        extendedBolusAbsoluteRemaining: Double(data.uint16(at: DataStart + 11)) / 100,
        insulinOnBoard: Double(data.uint16(at: DataStart + 13)) / 100,
        errorState: data.count > 17 ? Int(data[DataStart + 15]) : nil
    ))
}
