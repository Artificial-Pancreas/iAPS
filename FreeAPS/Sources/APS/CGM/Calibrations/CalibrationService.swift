import Foundation
import Swinject

struct Calibration: JSON, Equatable {
    let x: Double
    let y: Double
    var date = Date()

    static let zero = Calibration(x: 0, y: 0)
}

protocol CalibrationService {
    var slope: Double { get }
    var intercept: Double { get }
    var calibrations: [Calibration] { get }

    func addCalibration(_ calibration: Calibration)
    func removeCalibration(_ calibration: Calibration)
    func removeAllCalibrations()
    func removeLast()

    func calibrate(value: Double) -> Double
}

final class BaseCalibrationService: CalibrationService, Injectable {
    @Injected() var storage: FileStorage!

    private(set) var calibrations: [Calibration] = [] {
        didSet {
            storage.save(calibrations, as: OpenAPS.FreeAPS.calibrations)
        }
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        calibrations = storage.retrieve(OpenAPS.FreeAPS.calibrations, as: [Calibration].self) ?? []
    }

    var slope: Double {
        guard calibrations.count >= 2 else {
            return 1
        }

        let xs = calibrations.map(\.x)
        let ys = calibrations.map(\.y)
        let sum1 = average(multiply(xs, ys)) - average(xs) * average(ys)
        let sum2 = average(multiply(xs, xs)) - pow(average(xs), 2)
        let slope = sum1 / sum2

        return slope
    }

    var intercept: Double {
        guard calibrations.count >= 1 else {
            return 0
        }
        let xs = calibrations.map(\.x)
        let ys = calibrations.map(\.y)

        let intercept = average(ys) - slope * average(xs)

        return intercept
    }

    func calibrate(value: Double) -> Double {
        linearRegression(value)
    }

    func addCalibration(_ calibration: Calibration) {
        calibrations.append(calibration)
    }

    func removeCalibration(_ calibration: Calibration) {
        calibrations.removeAll { $0 == calibration }
    }

    func removeAllCalibrations() {
        calibrations.removeAll()
    }

    func removeLast() {
        calibrations.removeLast()
    }

    private func average(_ input: [Double]) -> Double {
        input.reduce(0, +) / Double(input.count)
    }

    private func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        zip(a, b).map(*)
    }

    private func linearRegression(_ x: Double) -> Double {
        intercept + slope * x
    }
}
