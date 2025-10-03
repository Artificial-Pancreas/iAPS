struct GetDeviceTypeResponse {
    let deviceType: UInt8
    let deviceSN: Data
}

class GetDeviceTypePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = GetDeviceTypeResponse
    let commandType: UInt8 = CommandType.GET_DEVICE_TYPE

    func getRequestBytes() -> Data {
        Data()
    }

    func parseResponse() -> GetDeviceTypeResponse {
        GetDeviceTypeResponse(
            deviceType: totalData[6],
            deviceSN: totalData[7 ..< 11]
        )
    }
}
