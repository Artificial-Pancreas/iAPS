struct SetBolusMotorResponse {}

/// Unused packet
class SetBolusMotorPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SetBolusMotorResponse
    let commandType: UInt8 = CommandType.SET_BOLUS_MOTOR

    func getRequestBytes() -> Data {
        Data([])
    }

    func parseResponse() -> SetBolusMotorResponse {
        SetBolusMotorResponse()
    }
}
