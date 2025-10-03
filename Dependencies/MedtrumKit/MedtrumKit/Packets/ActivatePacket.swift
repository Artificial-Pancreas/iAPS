struct ActivatePacketResponse {
    let patchId: Data
    let time: Date
    let basalType: BasalType
    let basalValue: Double
    let basalSequence: Double
    let basalPatchId: Double
    let basalStartTime: Date
}

class ActivatePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = ActivatePacketResponse

    let commandType: UInt8 = CommandType.ACTIVATE

    let autoSuspendEnable: UInt8 = 0
    let autoSuspendTime: UInt8 = 12 // unknown why this value needs to be this
    let expirationTimer: UInt8
    let alarmSetting: AlarmSettings
    let lowSuspend: UInt8 = 0
    let predictiveLowSuspend: UInt8 = 0
    let predictiveLowSuspendRange: UInt8 = 30 // Not sure why, but pump needs this in order to activate
    let hourlyMaxInsulin: Double
    let dailyMaxInsulin: Double
    let currentTDD: Double
    let basalProfile: Data

    init(
        expirationTimer: UInt8,
        alarmSetting: AlarmSettings,
        hourlyMaxInsulin: Double,
        dailyMaxInsulin: Double,
        currentTDD: Double,
        basalProfile: Data
    ) {
        self.expirationTimer = expirationTimer
        self.alarmSetting = alarmSetting
        self.hourlyMaxInsulin = hourlyMaxInsulin
        self.dailyMaxInsulin = dailyMaxInsulin
        self.currentTDD = currentTDD
        self.basalProfile = basalProfile
    }

    /**
     * byte 1: autoSuspendEnable -> Value for auto mode, not used for LoopKit
     * byte 2: autoSuspendTime -> Value for auto mode, not used for LoopKit
     * byte 3: expirationTimer -> Expiration timer, 0 = no expiration 1 = 12 hour reminder and expiration after 3 days
     * byte 4: alarmSetting -> see AlarmSetting
     * byte 5: lowSuspend -> Value for auto mode, not used for LoopKit
     * byte 6: predictiveLowSuspend -> Value for auto mode, not used for LoopKit
     * byte 7: predictiveLowSuspendRange -> Value for auto mode, not used for LoopKit
     * byte 8-9: hourlyMaxInsulin -> Max hourly dose of insulin, divided by 0.05
     * byte 10-11: dailyMaxSet -> Max daily dose of insulin, divided by 0.05
     * byte 12-13: tddToday -> Current TDD (of present day), divided by 0.05
     * byte 14: 1 -> Always 1
     * bytes 15 - end -> Basal profile
     */
    func getRequestBytes() -> Data {
        var base = Data([
            autoSuspendEnable,
            autoSuspendTime,
            expirationTimer,
            alarmSetting.rawValue,
            lowSuspend,
            predictiveLowSuspend,
            predictiveLowSuspendRange
        ])

        let calcHourlyInsulin = UInt16(round(hourlyMaxInsulin / 0.05))
        base.append(Data([
            UInt8(calcHourlyInsulin & 0xFF),
            UInt8(calcHourlyInsulin >> 8)
        ]))

        let calcDailyMaxInsulin = UInt16(round(dailyMaxInsulin / 0.05))
        base.append(Data([
            UInt8(calcDailyMaxInsulin & 0xFF),
            UInt8(calcDailyMaxInsulin >> 8)
        ]))

        let calcCurrentTDD = UInt16(round(currentTDD / 0.05))
        base.append(Data([
            UInt8(calcCurrentTDD & 0xFF),
            UInt8(calcCurrentTDD >> 8),
            1
        ]))

        return base + basalProfile
    }

    func parseResponse() -> ActivatePacketResponse {
        ActivatePacketResponse(
            patchId: totalData.subdata(in: 6 ..< 10),
            time: Date.fromMedtrumSeconds(totalData.subdata(in: 10 ..< 14).toUInt64()),
            basalType: BasalType(rawValue: totalData[14]) ?? .NONE,
            basalValue: totalData.subdata(in: 15 ..< 17).toDouble() * 0.05,
            basalSequence: totalData.subdata(in: 17 ..< 19).toDouble(),
            basalPatchId: totalData.subdata(in: 19 ..< 21).toDouble(),
            basalStartTime: Date.fromMedtrumSeconds(totalData.subdata(in: 21 ..< 25).toUInt64())
        )
    }
}
