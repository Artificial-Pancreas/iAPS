struct SuspendPumpResponse {}

class SuspendPumpPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SuspendPumpResponse
    let commandType: UInt8 = CommandType.SUSPEND_PUMP

    let duration: TimeInterval
    init(duration: TimeInterval) {
        self.duration = duration
    }

    func getRequestBytes() -> Data {
        // 3 -> cause: unknown why this is 3
        Data([3, UInt8(duration.minutes)])
    }

    func parseResponse() -> SuspendPumpResponse {
        SuspendPumpResponse()
    }
}
