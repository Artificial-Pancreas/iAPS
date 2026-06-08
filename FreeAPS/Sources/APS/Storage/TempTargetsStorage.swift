import Foundation
import SwiftDate
import Swinject

// protocol TempTargetsObserver: Sendable {
//    func tempTargetsDidUpdate(_ targets: [TempTarget])
// }

protocol TempTargetsStorage: Sendable {
    func storeTempTargets(_ targets: [TempTarget]) async
    func syncDate() async -> Date
    func recent() async -> [TempTarget]
    func nightscoutTretmentsNotUploaded() async -> [NigtscoutTreatment]
    func storePresets(_ targets: [TempTarget]) async
    func presets() async -> [TempTarget]
    func current() async -> TempTarget?
}

actor BaseTempTargetsStorage: TempTargetsStorage {
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    init(
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    func storeTempTargets(_ targets: [TempTarget]) async {
        await storeTempTargets(targets, isPresets: false)
    }

    private func storeTempTargets(_ targets: [TempTarget], isPresets: Bool) async {
        var targets = targets
        if !isPresets {
            if await current() != nil, let newActive = targets.last(where: {
                $0.createdAt.addingTimeInterval(Int($0.duration).minutes.timeInterval) > Date()
                    && $0.createdAt <= Date()
            }) {
                // cancel current
                targets += [TempTarget.cancel(at: newActive.createdAt.addingTimeInterval(-1))]
            }
        }

        let file = isPresets ? OpenAPS.FreeAPS.tempTargetsPresets : OpenAPS.Settings.tempTargets
        let uniqEvents: [TempTarget] = await self.storage.appendAndModify(targets, to: file, uniqBy: \.createdAt) {
            $0
                .filter {
                    guard !isPresets else { return true }
                    return $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date()
                }
                .sorted { $0.createdAt > $1.createdAt }
        }
        await appCoordinator.tempTargetsUpdates.send(uniqEvents)
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recent() async -> [TempTarget] {
        await storage.retrieve(OpenAPS.Settings.tempTargets, as: [TempTarget].self)?.reversed() ?? []
    }

    func current() async -> TempTarget? {
        guard let last = await recent().last else {
            return nil
        }

        guard last.createdAt.addingTimeInterval(Int(last.duration).minutes.timeInterval) > Date(), last.createdAt <= Date(),
              last.duration != 0
        else {
            return nil
        }

        return last
    }

    func nightscoutTretmentsNotUploaded() async -> [NigtscoutTreatment] {
        let uploaded = await storage.retrieve(OpenAPS.Nightscout.uploadedTempTargets, as: [NigtscoutTreatment].self) ?? []

        let eventsManual = await recent().filter { $0.enteredBy == TempTarget.manual }
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: Int($0.duration),
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsTempTarget,
                createdAt: $0.createdAt,
                enteredBy: TempTarget.manual,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                targetTop: $0.targetTop,
                targetBottom: $0.targetBottom
            )
        }
        return Array(Set(treatments).subtracting(Set(uploaded)))
    }

    func storePresets(_ targets: [TempTarget]) async {
        // TODO: implement as one call/write - .replace?
        await storage.remove(OpenAPS.FreeAPS.tempTargetsPresets)
        await storeTempTargets(targets, isPresets: true)
    }

    func presets() async -> [TempTarget] {
        await storage.retrieve(OpenAPS.FreeAPS.tempTargetsPresets, as: [TempTarget].self)?.reversed() ?? []
    }
}
