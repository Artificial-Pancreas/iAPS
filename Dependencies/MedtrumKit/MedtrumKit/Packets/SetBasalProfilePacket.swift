struct SetBasalProfilePacketResponse {
    let basalType: BasalType
    let basalValue: Double
    let basalSequence: Double
    let basalPatchId: Double
    let basalStartTime: Date
}

class SetBasalProfilePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SetBasalProfilePacketResponse

    let commandType: UInt8 = CommandType.SET_BASAL_PROFILE
    let basalType: UInt8 = 1 // Fixed to normal basal profile
    let basalProfile: Data

    init(basalProfile: Data) {
        self.basalProfile = basalProfile
    }

    func getRequestBytes() -> Data {
        Data([basalType]) + basalProfile
    }

    func parseResponse() -> SetBasalProfilePacketResponse {
        SetBasalProfilePacketResponse(
            basalType: BasalType(rawValue: totalData[6]) ?? .NONE,
            basalValue: totalData.subdata(in: 7 ..< 9).toDouble() * 0.05,
            basalSequence: totalData.subdata(in: 9 ..< 11).toDouble(),
            basalPatchId: totalData.subdata(in: 11 ..< 13).toDouble(),
            basalStartTime: Date.fromMedtrumSeconds(totalData.subdata(in: 13 ..< 17).toUInt64())
        )
    }
}
