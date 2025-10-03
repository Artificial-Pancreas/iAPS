struct ResumePumpPacketResponse {}

class ResumePumpPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = ResumePumpPacketResponse
    let commandType: UInt8 = CommandType.RESUME_PUMP

    func getRequestBytes() -> Data {
        Data()
    }

    func parseResponse() -> ResumePumpPacketResponse {
        ResumePumpPacketResponse()
    }
}
