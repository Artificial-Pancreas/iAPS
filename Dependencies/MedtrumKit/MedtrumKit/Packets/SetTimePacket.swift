struct SetTimePacketResponse {}

class SetTimePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SetTimePacketResponse

    let commandType: UInt8 = CommandType.SET_TIME
    let date: Date

    init(date: Date) {
        self.date = date
    }

    func getRequestBytes() -> Data {
        var output = Data([2])
        output.append(date.toMedtrumSeconds())

        return output
    }

    func parseResponse() -> SetTimePacketResponse {
        SetTimePacketResponse()
    }
}
