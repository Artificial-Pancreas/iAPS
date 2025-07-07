struct GetTimePacketResponse {
    let time: Date
}

class GetTimePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = GetTimePacketResponse

    let commandType: UInt8 = CommandType.GET_TIME

    func getRequestBytes() -> Data {
        Data()
    }

    func parseResponse() -> GetTimePacketResponse {
        let secondsPassed = totalData.subdata(in: 6 ..< 10).toUInt64()
        return GetTimePacketResponse(
            time: Date.fromMedtrumSeconds(secondsPassed)
        )
    }
}
