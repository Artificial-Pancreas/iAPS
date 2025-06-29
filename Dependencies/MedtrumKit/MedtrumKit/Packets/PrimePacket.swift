struct PrimePacketResponse {}

class PrimePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = PrimePacketResponse

    let commandType: UInt8 = CommandType.PRIME

    func getRequestBytes() -> Data {
        Data([])
    }

    func parseResponse() -> PrimePacketResponse {
        PrimePacketResponse()
    }
}
