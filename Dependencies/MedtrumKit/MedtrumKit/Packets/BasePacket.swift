protocol MedtrumBasePacketProtocol {
    associatedtype T

    var commandType: UInt8 { get }

    // Needed to parse
    var dataSize: UInt8 { get set }
    var totalData: Data { get set }
    var sequenceNumber: UInt8 { get set }
    var responseCode: UInt16 { get set }
    var failed: Bool { get set }

    func getRequestBytes() -> Data
    func parseResponse() -> T
}

class MedtrumBasePacket {
    var dataSize: UInt8 = 0
    var responseCode: UInt16 = 0
    var totalData = Data()
    var sequenceNumber: UInt8 = 0
    var failed: Bool = false
}

extension MedtrumBasePacketProtocol {
    func encode(sequenceNumber: UInt8) -> [Data] {
        let content = getRequestBytes()
        var header = Data([
            UInt8(content.count + 5),
            commandType,
            sequenceNumber,
            0 // pkgIndex
        ])

        let tmp = header + content
        let totalCommand = tmp + Crc8.calculate(tmp)

        if (totalCommand.count - header.count) <= 15 {
            let output = totalCommand + Data([0])
            return [output]
        }

        // We need to split up the command in multiple packages
        var packages: [Data] = []

        var pkgIndex: UInt8 = 1
        var remainingCommand = totalCommand.subdata(in: 4 ..< totalCommand.count)

        while remainingCommand.count > 15 {
            header[3] = pkgIndex

            let tmp2 = header + remainingCommand.subdata(in: 0 ..< 15)
            packages.append(tmp2 + Crc8.calculate(tmp2))

            remainingCommand = remainingCommand.subdata(in: 15 ..< remainingCommand.count)
            pkgIndex = UInt8(pkgIndex + 1)
        }

        header[3] = pkgIndex
        let tmp3 = header + remainingCommand

        packages.append(tmp3 + Crc8.calculate(tmp3))
        return packages
    }

    mutating func decode(_ data: Data) {
        if totalData.isEmpty {
            if data[1] != commandType {
                failed = true
            }

            totalData = data.subdata(in: 0 ..< data.count - 1)
            dataSize = data[0]
            sequenceNumber = data[3]

            responseCode = UInt16(data.subdata(in: 4 ..< 6).toUInt64())

            let initialCrc = Crc8.calculate(data[0 ..< data.count - 1])
            if initialCrc[0] != data[data.count - 1] {
                failed = true
            }
            return
        }

        totalData.append(data[4 ..< data.count - 1])
        sequenceNumber += 1

        let newCrc = Crc8.calculate(data[0 ..< data.count - 1])
        if newCrc[0] != data[data.count - 1] {
            failed = true
        }
        if sequenceNumber != data[3] {
            failed = true
        }
    }

    var isComplete: Bool {
        totalData.count == dataSize
    }
}
