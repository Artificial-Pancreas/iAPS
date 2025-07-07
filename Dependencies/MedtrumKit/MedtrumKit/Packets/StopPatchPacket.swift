struct StopPatchResponse {
    let sequence: Double
    let patchId: Double
}

class StopPatchPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = StopPatchResponse
    let commandType: UInt8 = CommandType.STOP_PATCH

    func getRequestBytes() -> Data {
        Data()
    }

    func parseResponse() -> StopPatchResponse {
        StopPatchResponse(
            sequence: totalData.subdata(in: 6 ..< 8).toDouble(),
            patchId: totalData.subdata(in: 8 ..< 10).toDouble()
        )
    }
}
