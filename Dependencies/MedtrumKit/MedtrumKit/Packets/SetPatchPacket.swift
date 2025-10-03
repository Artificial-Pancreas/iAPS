struct SetPatchResponse {}

class SetPatchPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SetPatchResponse
    let commandType: UInt8 = CommandType.SET_PATCH

    let alarmSettings: AlarmSettings
    let hourlyMaxInsulin: Double
    let dailyMaxInsulin: Double
    let expirationTimer: UInt8
    let autoSuspendEnable: UInt8 = 0
    let autoSuspendTime: UInt8 = 12
    let lowSuspend: UInt8 = 0
    let predictiveLowSuspend: UInt8 = 0
    let predictiveLowSuspendRange: UInt8 = 30

    init(alarmSettings: AlarmSettings, hourlyMaxInsulin: Double, dailyMaxInsulin: Double, expirationTimer: UInt8) {
        self.alarmSettings = alarmSettings
        self.hourlyMaxInsulin = hourlyMaxInsulin
        self.dailyMaxInsulin = dailyMaxInsulin
        self.expirationTimer = expirationTimer
    }

    func getRequestBytes() -> Data {
        var base = Data([
            alarmSettings.rawValue
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

        base.append(Data([
            expirationTimer,
            autoSuspendEnable,
            autoSuspendTime,
            lowSuspend,
            predictiveLowSuspend,
            predictiveLowSuspendRange
        ]))

        return base
    }

    func parseResponse() -> SetPatchResponse {
        SetPatchResponse()
    }
}
