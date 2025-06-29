struct SubscribePacketResponse {}

class SubscribePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SubscribePacketResponse

    let commandType: UInt8 = CommandType.SUBSCRIBE

    func getRequestBytes() -> Data {
        UInt64(4095).toData(length: 2)
    }

    func parseResponse() -> SubscribePacketResponse {
        SubscribePacketResponse()
    }
}
