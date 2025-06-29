struct SetBolusResponse {}

class SetBolusPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SetBolusResponse
    let commandType: UInt8 = CommandType.SET_BOLUS

    // Bolus types:
    // 1 = normal
    // 2 = Extended
    // 3 = Combi
    let bolusType: UInt8 = 1
    let bolusAmount: Double

    init(bolusAmount: Double) {
        self.bolusAmount = bolusAmount
    }

    func getRequestBytes() -> Data {
        let amount = UInt64(round(bolusAmount / 0.05)).toData(length: 2)
        var output = Data([bolusType])
        output.append(amount)
        output.append(Data([0]))

        return output
    }

    func parseResponse() -> SetBolusResponse {
        SetBolusResponse()
    }
}
