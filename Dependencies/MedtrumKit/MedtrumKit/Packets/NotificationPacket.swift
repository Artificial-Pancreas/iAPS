struct SynchronizePacketResponse: Codable {
    let state: PatchState
    var suspendTime: Date?
    var bolus: BolusData?
    var basal: BasalData?
    var primeProgress: UInt8?
    var reservoir: Double?
    var startTime: Date?
    var battery: BatteryData?
    var storage: StorageData?
    var activeAlarms: [AlarmState]
    var patchAge: UInt64?
    var magnetoPlacement: Double?
}

struct BolusData: Codable {
    let type: UInt8
    let completed: Bool
    let delivered: Double
}

struct BasalData: Codable {
    let type: BasalType
    let sequence: Double
    let patchId: Double
    let startTime: Date
    let rate: Double
    let delivery: Double
}

struct BatteryData: Codable {
    let voltageA: Double
    let voltageB: Double
}

struct StorageData: Codable {
    let sequence: Double
    let patchId: Double
}

let MASK_SUSPEND: UInt16 = 0x01
let MASK_NORMAL_BOLUS: UInt16 = 0x02
let MASK_EXTENDED_BOLUS: UInt16 = 0x04
let MASK_BASAL: UInt16 = 0x08
let MASK_SETUP: UInt16 = 0x10
let MASK_RESERVOIR: UInt16 = 0x20
let MASK_START_TIME: UInt16 = 0x40
let MASK_BATTERY: UInt16 = 0x80
let MASK_STORAGE: UInt16 = 0x100
let MASK_ALARM: UInt16 = 0x200
let MASK_AGE: UInt16 = 0x400
let MASK_MAGNETO_PLACE: UInt16 = 0x800
let MASK_UNUSED_CGM: UInt16 = 0x1000
let MASK_UNUSED_COMMAND_CONFIRM: UInt16 = 0x2000
let MASK_UNUSED_AUTO_STATUS: UInt16 = 0x4000
let MASK_UNUSED_LEGACY: UInt16 = 0x8000

class NotificationPacket: MedtrumBasePacket, MedtrumBasePacketProtocol {
    typealias T = SynchronizePacketResponse

    let commandType: UInt8 = CommandType.SYNCHRONIZE

    func getRequestBytes() -> Data {
        Data()
    }

    func parseResponse() -> SynchronizePacketResponse {
        handle(
            state: PatchState(rawValue: totalData[0]) ?? .none,
            fieldMask: UInt16(totalData.subdata(in: 1 ..< 3).toUInt64()),
            syncData: Data(totalData.dropFirst(3))
        )
    }

    public func handle(state: PatchState, fieldMask: UInt16, syncData: Data) -> SynchronizePacketResponse {
        var offset = 0

        var output = SynchronizePacketResponse(
            state: state,
            suspendTime: nil,
            bolus: nil,
            basal: nil,
            primeProgress: nil,
            reservoir: nil,
            startTime: nil,
            battery: nil,
            storage: nil,
            activeAlarms: [],
            patchAge: nil,
            magnetoPlacement: nil
        )

        // Proces masks
        for (mask, handler) in maskHandlers.sorted(by: { $0.key < $1.key }) {
            if fieldMask & mask != 0 {
                offset = handler(syncData, offset, &output)
            }
        }

        return output
    }

    private let maskHandlers: [UInt16: (Data, Int, inout SynchronizePacketResponse) -> Int] = [
        MASK_SUSPEND: { data, offset, output in
            output.suspendTime = Date.fromMedtrumSeconds(data.subdata(in: offset ..< offset + 4).toUInt64())
            return offset + 4
        },
        MASK_NORMAL_BOLUS: { data, offset, output in
            output.bolus = BolusData(
                type: data[offset] & 0x7F,
                completed: data[offset] & 0x80 != 0,
                delivered: data.subdata(in: offset + 1 ..< offset + 3).toDouble() * 0.05
            )
            return offset + 3
        },
        MASK_EXTENDED_BOLUS: { _, offset, _ in
            // Just ignore this flag
            offset + 3
        },
        MASK_BASAL: { data, offset, output in
            let rateDelivery = UInt32(data.subdata(in: offset + 9 ..< offset + 12).toDouble())
            let delivery = rateDelivery >> 12
            let rate = rateDelivery & 0x0FFF

            output.basal = BasalData(
                type: BasalType(rawValue: data[offset]) ?? .NONE,
                sequence: data.subdata(in: offset + 1 ..< offset + 3).toDouble(),
                patchId: data.subdata(in: offset + 3 ..< offset + 5).toDouble(),
                startTime: Date.fromMedtrumSeconds(data.subdata(in: offset + 5 ..< offset + 9).toUInt64()),
                rate: Double(rate) * 0.05,
                delivery: Double(delivery) * 0.05
            )

            return offset + 12
        },
        MASK_SETUP: { data, offset, output in
            output.primeProgress = data[offset]
            return offset + 1
        },
        MASK_RESERVOIR: { data, offset, output in
            output.reservoir = data.subdata(in: offset ..< offset + 2).toDouble() * 0.05
            return offset + 2
        },
        MASK_START_TIME: { data, offset, output in
            output.startTime = Date.fromMedtrumSeconds(data.subdata(in: offset ..< offset + 4).toUInt64())
            return offset + 4
        },
        MASK_BATTERY: { data, offset, output in
            let value = UInt32(data.subdata(in: offset ..< offset + 3).toUInt64())

            output.battery = BatteryData(
                voltageA: Double(value & 0x0FFF) / 512,
                voltageB: Double(value >> 12) / 512
            )
            return offset + 3
        },
        MASK_STORAGE: { data, offset, output in
            output.storage = StorageData(
                sequence: data.subdata(in: offset ..< offset + 2).toDouble(),
                patchId: data.subdata(in: offset + 2 ..< offset + 4).toDouble()
            )
            return offset + 4
        },
        MASK_ALARM: { data, offset, output in
            let flags = UInt16(data.subdata(in: offset ..< offset + 2).toUInt64())
            if flags != AlarmState.None.rawValue {
                // Alarms list available, only need to check the first 3
                for i in 0 ..< 3 {
                    if flags & (1 << i) != 0, let alarmState = AlarmState(rawValue: 1 << i) {
                        output.activeAlarms.append(alarmState)
                    }
                }
            }

            // Unused parameter
            let _parameter = data.subdata(in: offset + 2 ..< offset + 4)
            return offset + 4
        },
        MASK_AGE: { data, offset, output in
            output.patchAge = data.subdata(in: offset ..< offset + 4).toUInt64()
            return offset + 4
        },
        MASK_MAGNETO_PLACE: { data, offset, output in
            output.magnetoPlacement = data.subdata(in: offset ..< offset + 2).toDouble()
            return offset + 2
        },
        MASK_UNUSED_CGM: { _, offset, _ in
            offset + 5
        },
        MASK_UNUSED_COMMAND_CONFIRM: { _, offset, _ in
            offset + 2
        },
        MASK_UNUSED_AUTO_STATUS: { _, offset, _ in
            offset + 2
        },
        MASK_UNUSED_LEGACY: { _, offset, _ in
            offset + 2
        }
    ]
}
