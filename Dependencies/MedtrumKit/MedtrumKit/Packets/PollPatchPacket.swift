struct PollPatchPacketResponse {}

class PollPatchPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = PollPatchPacketResponse

    let commandType: UInt8 = CommandType.POLL_PATCH

    func getRequestBytes() -> Data {
        Data([])
    }

    func parseResponse() -> PollPatchPacketResponse {
        PollPatchPacketResponse()
    }
}
