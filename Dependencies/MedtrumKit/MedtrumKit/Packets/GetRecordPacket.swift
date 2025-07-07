struct GetRecordPacketResponse {
    let header: UInt8
    let unknown: UInt8
    let type: UInt8
    let unknown1: UInt8
    let serial: Data
    let patchId: Data
    let sequence: UInt16
}

class GetRecordPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = GetRecordPacketResponse
    let commandType: UInt8 = CommandType.GET_RECORD

    let recordIndex: UInt16
    let patchId: Data

    init(recordIndex: UInt16, patchId: Data) {
        self.recordIndex = recordIndex
        self.patchId = patchId
    }

    func getRequestBytes() -> Data {
        Data([
            UInt8(recordIndex & 0xFF),
            UInt8(recordIndex >> 8)
        ]) + patchId
    }

    func parseResponse() -> GetRecordPacketResponse {
        GetRecordPacketResponse(
            header: totalData[6],
            unknown: totalData[7],
            type: totalData[8],
            unknown1: totalData[9],
            serial: totalData.subdata(in: 10 ..< 14),
            patchId: totalData.subdata(in: 14 ..< 16),
            sequence: UInt16(totalData.subdata(in: 16 ..< 18).toUInt64())
        )
    }
}
