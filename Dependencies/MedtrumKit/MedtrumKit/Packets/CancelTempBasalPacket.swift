struct CancelTempBasalPacketResponse {
    let basalType: BasalType
    let basalValue: Double
    let basalSequence: Double
    let basalPatchId: Double
    let basalStartTime: Date
}

class CancelTempBasalPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = CancelTempBasalPacketResponse

    let commandType: UInt8 = CommandType.CANCEL_TEMP_BASAL

    func getRequestBytes() -> Data {
        Data([])
    }

    func parseResponse() -> CancelTempBasalPacketResponse {
        CancelTempBasalPacketResponse(
            basalType: BasalType(rawValue: totalData[6]) ?? .NONE,
            basalValue: totalData.subdata(in: 7 ..< 9).toDouble() * 0.05,
            basalSequence: totalData.subdata(in: 9 ..< 11).toDouble(),
            basalPatchId: totalData.subdata(in: 11 ..< 13).toDouble(),
            basalStartTime: Date.fromMedtrumSeconds(totalData.subdata(in: 13 ..< 17).toUInt64())
        )
    }
}
