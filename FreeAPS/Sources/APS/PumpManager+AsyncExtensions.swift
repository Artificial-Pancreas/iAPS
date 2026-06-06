@preconcurrency import LoopKit
@preconcurrency import LoopKitUI

extension PumpManager {
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { error in
                if let error {
                    debug(.apsManager, "Temp basal failed: \(unitsPerHour) for: \(duration)")
                    continuation.resume(throwing: APSError.pumpError(error))
                } else {
                    debug(.apsManager, "Temp basal succeeded: \(unitsPerHour) for: \(duration)")
                    continuation.resume()
                }
            }
        }
    }

    func enactBolus(units: Double, automatic: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // convert automatic
            let automaticValue = automatic ? BolusActivationType.automatic : BolusActivationType.manualRecommendationAccepted

            self.enactBolus(units: units, activationType: automaticValue) { error in
                if let error {
                    debug(.apsManager, "Bolus failed: \(units)")
                    continuation.resume(throwing: APSError.pumpError(error))
                } else {
                    debug(.apsManager, "Bolus succeeded: \(units)")
                    continuation.resume()
                }
            }
        }
    }

    func cancelBolus() async throws -> DoseEntry? {
        try await withCheckedThrowingContinuation { continuation in
            self.cancelBolus { result in
                switch result {
                case let .success(dose):
                    debug(.apsManager, "Cancel Bolus succeeded")
                    continuation.resume(returning: dose)
                case let .failure(error):
                    debug(.apsManager, "Cancel Bolus failed")
                    continuation.resume(throwing: APSError.pumpError(error))
                }
            }
        }
    }

    func suspendDelivery() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.suspendDelivery { error in
                if let error {
                    continuation.resume(throwing: APSError.pumpError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func resumeDelivery() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.resumeDelivery { error in
                if let error {
                    continuation.resume(throwing: APSError.pumpError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
