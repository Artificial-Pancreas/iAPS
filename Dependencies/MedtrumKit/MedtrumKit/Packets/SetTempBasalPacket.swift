struct SetTempBasalResponse {
    let basalType: BasalType
    let basalValue: Double
    let basalSequence: Double
    let basalPatchId: Double
    let basalStartTime: Date
}

class SetTempBasalPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SetTempBasalResponse
    let commandType: UInt8 = CommandType.SET_TEMP_BASAL

    let type: UInt8 = 6 // Fixed to temp basal value for now
    let rate: Double
    let duration: TimeInterval

    init(rate: Double, duration: TimeInterval) {
        self.rate = rate
        self.duration = duration
    }

    func getRequestBytes() -> Data {
        var base = Data([type])

        let tempBasalRate = UInt64(round(rate / 0.05)).toData(length: 2)
        base.append(tempBasalRate)

        let tempBasalDuration = UInt64(duration.minutes).toData(length: 2)
        base.append(tempBasalDuration)

        return base
    }

    func parseResponse() -> SetTempBasalResponse {
        SetTempBasalResponse(
            basalType: BasalType(rawValue: totalData[6]) ?? .NONE,
            basalValue: totalData.subdata(in: 7 ..< 9).toDouble() * 0.05,
            basalSequence: totalData.subdata(in: 9 ..< 11).toDouble(),
            basalPatchId: totalData.subdata(in: 11 ..< 13).toDouble(),
            basalStartTime: Date.fromMedtrumSeconds(totalData.subdata(in: 13 ..< 17).toUInt64())
        )
    }
}
