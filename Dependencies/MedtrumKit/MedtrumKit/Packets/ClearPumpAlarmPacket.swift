struct ClearPumpAlarmResponse {}

class ClearPumpAlarmPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = ClearPumpAlarmResponse

    let commandType: UInt8 = CommandType.CLEAR_ALARM

    private let alarmType: ClearAlarmType

    init(alarmType: ClearAlarmType) {
        self.alarmType = alarmType
    }

    func getRequestBytes() -> Data {
        Data([alarmType.rawValue])
    }

    func parseResponse() -> ClearPumpAlarmResponse {
        ClearPumpAlarmResponse()
    }
}
