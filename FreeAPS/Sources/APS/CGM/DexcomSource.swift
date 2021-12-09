import CGMBLEKit
import Combine
import Foundation

final class DexcomSource: GlucoseSource {
    private let processQueue = DispatchQueue(label: "DexcomSource.processQueue")

    private let dexcomManager = TransmitterManager(
        state: TransmitterManagerState(transmitterID: UserDefaults.standard.dexcomTransmitterID ?? "000000")
    )

    private var promise: Future<[BloodGlucose], Error>.Promise?

    init() {
        dexcomManager.delegate = self
    }

    var transmitterID: String {
        dexcomManager.transmitter.ID
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        dexcomManager.transmitter.resumeScanning()
        return Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    deinit {
        dexcomManager.transmitter.stopScanning()
    }
}

extension DexcomSource: TransmitterManagerDelegate {
    func transmitterManager(_: TransmitterManager, didFailWith error: Error) {
        promise?(.failure(error))
    }

    func transmitterManager(_: TransmitterManager, didRead glucose: [CGMBLEKit.Glucose]) {
        let bloodGlucose = glucose.compactMap { glucose -> BloodGlucose? in
            guard let quantity = glucose.glucose else {
                return nil
            }
            let value = Int(quantity.doubleValue(for: .milligramsPerDeciliter))

            return BloodGlucose(
                _id: glucose.syncIdentifier,
                sgv: value,
                direction: .init(trend: glucose.trend),
                date: Decimal(Int(glucose.readDate.timeIntervalSince1970 * 1000)),
                dateString: glucose.readDate,
                unfiltered: nil,
                filtered: nil,
                noise: nil,
                glucose: value,
                type: "sgv"
            )
        }
        promise?(.success(bloodGlucose))
    }

    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Dexcom tramsmitter ID: \(transmitterID)"]
    }
}

extension BloodGlucose.Direction {
    init(trend: Int) {
        guard trend < Int(Int8.max) else {
            self = .none
            return
        }

        switch trend {
        case let x where x <= -30:
            self = .doubleDown
        case let x where x <= -20:
            self = .singleDown
        case let x where x <= -10:
            self = .fortyFiveDown
        case let x where x < 10:
            self = .flat
        case let x where x < 20:
            self = .fortyFiveUp
        case let x where x < 30:
            self = .singleUp
        default:
            self = .doubleUp
        }
    }
}
