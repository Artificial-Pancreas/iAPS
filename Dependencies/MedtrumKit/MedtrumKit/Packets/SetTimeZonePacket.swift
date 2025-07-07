struct SetTimeZonePacketResponse {}

class SetTimeZonePacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SetTimeZonePacketResponse

    let commandType: UInt8 = CommandType.SET_TIME_ZONE
    let date: Date
    let timeZone: TimeZone

    init(date: Date, timeZone: TimeZone) {
        self.date = date
        self.timeZone = timeZone
    }

    func getRequestBytes() -> Data {
        var offset = TimeInterval(seconds: Double(timeZone.secondsFromGMT(for: date)))

        // Workaround for bug where it fails to set timezone > GMT + 12
        // if offset is > 12 hours, subtract 24 hours
        if offset > .hours(12) {
            offset -= .hours(24)
        }

        var offsetInMinutes = Int(offset.minutes)
        if offsetInMinutes < 0 {
            offsetInMinutes += 65536
        }

        let base = Data([
            UInt8(offsetInMinutes & 0xFF),
            UInt8(offsetInMinutes >> 8)
        ])

        return base + date.toMedtrumSeconds()
    }

    func parseResponse() -> SetTimeZonePacketResponse {
        SetTimeZonePacketResponse()
    }
}
