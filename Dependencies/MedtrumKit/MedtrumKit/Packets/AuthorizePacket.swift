struct AuthorizeResponse {
    let deviceType: UInt8
    let swVersion: String
}

class AuthorizePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = AuthorizeResponse

    let commandType: UInt8 = CommandType.AUTH_REQ

    private let role: UInt8 = 2
    private let pumpSN: Data
    private let sessionToken: Data

    init(pumpSN: Data, sessionToken: Data) {
        self.pumpSN = Data(pumpSN.reversed())
        self.sessionToken = sessionToken
    }

    func getRequestBytes() -> Data {
        let key = Crypto.genKey(pumpSN)

        var output = Data([role])
        output.append(sessionToken)
        output.append(key)

        return output
    }

    func parseResponse() -> AuthorizeResponse {
        AuthorizeResponse(
            deviceType: totalData[7],
            swVersion: "\(totalData[8]).\(totalData[9]).\(totalData[10])"
        )
    }
}
