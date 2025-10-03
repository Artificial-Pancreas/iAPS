struct ReadBolusStatePacketResponse {
    let bolusData: Data
}

class ReadBolusStatePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = ReadBolusStatePacketResponse
    let commandType: UInt8 = CommandType.READ_BOLUS_STATE

    func getRequestBytes() -> Data {
        Data()
    }

    func parseResponse() -> ReadBolusStatePacketResponse {
        ReadBolusStatePacketResponse(
            bolusData: totalData.subdata(in: 6 ..< totalData.count)
        )
    }
}
