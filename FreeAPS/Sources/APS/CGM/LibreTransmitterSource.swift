import Combine
import Foundation
import LibreTransmitter
import Swinject

protocol LibreTransmitterSource: GlucoseSource {
    var manager: LibreTransmitterManager? { get set }
}

final class BaseLibreTransmitterSource: LibreTransmitterSource, Injectable {
    private let processQueue = DispatchQueue(label: "BaseLibreTransmitterSource.processQueue")

    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var calibrationService: CalibrationService!

    private var promise: Future<[BloodGlucose], Error>.Promise?

    var manager: LibreTransmitterManager? {
        didSet {
            configured = manager != nil
            manager?.cgmManagerDelegate = self
        }
    }

    @Persisted(key: "LibreTransmitterManager.configured") private(set) var configured = false

    init(resolver: Resolver) {
        if configured {
            manager = LibreTransmitterManager()
            manager?.cgmManagerDelegate = self
        }

        injectServices(resolver)
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func sourceInfo() -> [String: Any]? {
        if let battery = manager?.battery {
            return ["transmitterBattery": battery]
        }
        return nil
    }
}

extension BaseLibreTransmitterSource: LibreTransmitterManagerDelegate {
    var queue: DispatchQueue { processQueue }

    func startDateToFilterNewData(for _: LibreTransmitterManager) -> Date? {
        glucoseStorage.syncDate()
    }

    func cgmManager(_ manager: LibreTransmitterManager, hasNew result: Result<[LibreGlucose], Error>) {
        switch result {
        case let .success(newGlucose):
            let glucose = newGlucose.map { value -> BloodGlucose in
                BloodGlucose(
                    _id: value.syncId,
                    sgv: Int(value.glucose),
                    direction: manager.glucoseDisplay?.trendType
                        .map { .init(trendType: $0) },
                    date: Decimal(Int(value.startDate.timeIntervalSince1970 * 1000)),
                    dateString: value.startDate,
                    unfiltered: Decimal(value.unsmoothedGlucose),
                    filtered: nil,
                    noise: nil,
                    glucose: Int(value.glucose),
                    type: "sgv"
                )
            }

            promise?(.success(glucose))

        case let .failure(error):
            warning(.service, "LibreTransmitter error:", error: error)
            promise?(.failure(error))
        }
    }

    func overcalibration(for _: LibreTransmitterManager) -> ((Double) -> (Double))? {
        calibrationService.calibrate
    }
}

extension BloodGlucose.Direction {
    init(trendType: GlucoseTrend) {
        switch trendType {
        case .upUpUp:
            self = .doubleUp
        case .upUp:
            self = .singleUp
        case .up:
            self = .fortyFiveUp
        case .flat:
            self = .flat
        case .down:
            self = .fortyFiveDown
        case .downDown:
            self = .singleDown
        case .downDownDown:
            self = .doubleDown
        }
    }
}
