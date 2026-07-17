import Foundation
import SwiftDate
import Swinject

protocol TempTargetsStorage: Sendable {
    func storeTempTargets(_ targets: [TempTarget]) async
    func syncDate() async -> Date
    func storePresets(_ targets: [TempTarget]) async
    func presets() async -> [TempTarget]
    func current() async -> TempTarget?
}

actor BaseTempTargetsStorage: TempTargetsStorage, AppService {
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    init(
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    // this is called on app start
    func start() async {
        // newest->oldest
        let history = await storage.retrieve(OpenAPS.Settings.tempTargets, as: [TempTarget].self) ?? []
        appCoordinator.setTempTargets(history)
    }

    func storeTempTargets(_ targets: [TempTarget]) async {
        await storeTempTargets(targets, isPresets: false)
    }

    private func storeTempTargets(_ targets: [TempTarget], isPresets: Bool) async {
        var targets = targets
        let now = Date()
        if !isPresets {
            if await current() != nil, let newActive = targets.last(where: {
                $0.createdAt.addingTimeInterval(.minutes(Int($0.duration))) > now
                    && $0.createdAt <= now
            }) {
                // cancel current
                targets += [TempTarget.cancel(at: newActive.createdAt.subtractingTimeInterval(.seconds(1)))]
            }
        }

        let file = isPresets ? OpenAPS.FreeAPS.tempTargetsPresets : OpenAPS.Settings.tempTargets
        let uniqEvents: [TempTarget] = await self.storage.appendAndModify(targets, to: file, uniqBy: \.createdAt) {
            $0
                .filter {
                    guard !isPresets else { return true }
                    return $0.createdAt > now.subtractingTimeInterval(.hours(24))
                }
                .sorted { $0.createdAt > $1.createdAt }
        }
        // newest->oldest
        appCoordinator.setTempTargets(uniqEvents)
    }

    func syncDate() -> Date {
        Date().subtractingTimeInterval(.hours(24))
    }

    func current() async -> TempTarget? {
        let history = await storage.retrieve(OpenAPS.Settings.tempTargets, as: [TempTarget].self) ?? []
        guard let current = history.first, current.isActive(at: Date()) else {
            return nil
        }
        return current
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
