struct CancelBolusPacketResponse {}

class CancelBolusPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = CancelBolusPacketResponse

    let commandType: UInt8 = CommandType.CANCEL_BOLUS

    /**
        1 -> Normal bolus
        2 -> Extended bolus
        3 -> Combi bolus
     */
    private let bolusType: UInt8 = 1

    func getRequestBytes() -> Data {
        Data([bolusType])
    }

    func parseResponse() -> CancelBolusPacketResponse {
        CancelBolusPacketResponse()
    }
}
