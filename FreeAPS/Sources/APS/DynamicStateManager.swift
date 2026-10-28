import Foundation

protocol DynamicStateManager: Sendable {
    /// `tempTargets`: the list the profiles are made from (one read per loop, so the HBT decision matches them).
    func dynamicVariables(tempTargets: [TempTarget]) async -> DynamicVariables
}

actor BaseDynamicStateManager: DynamicStateManager, LifetimeOwner, AppService {
    private let appCoordinator: AppCoordinator
    private let overrideStorage: OverrideStorage

    private let coreDataStorage = CoreDataStorage()

    let lifetime = Lifetime()

    init(
        appCoordinator: AppCoordinator,
        overrideStorage: OverrideStorage
    ) {
        self.appCoordinator = appCoordinator
        self.overrideStorage = overrideStorage
    }

    // this is called at the app start
    func start() async {}

    func dynamicVariables(tempTargets: [TempTarget]) async -> DynamicVariables {
        let preferences = appCoordinator.preferences.value

        let start = Date.now
        var hbt_ = preferences.halfBasalExerciseTarget
        let wp = preferences.weightPercentage
        let smbMinutes = preferences.maxSMBBasalMinutes
        let uamMinutes = preferences.maxUAMSMBBasalMinutes

        let currentTDD = TotalDailyDose().totalDailyDose(
            appCoordinator.pumpHistory.value,
            increment: Double(preferences.bolusIncrement)
        )
        if currentTDD.hours > 0 {
            await coreDataStorage.saveTDD(currentTDD)
        }

        var now = Date.now
        // TDD
        let uniqueEvents = await coreDataStorage.fetchTDD(interval: DateFilter.tenDays.startDate)
        print(
            "dynamicVariables: Time to fetch TDD \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Overrides
        now = Date.now
        let activeOverride = await overrideStorage.fetchCurrentActiveOverride()
        print(
            "dynamicVariables: Time for fetchCurrentActiveOverride \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Temp Target: only the HBT row of the active temp target applies (one left by a temp target that was
        // replaced or cancelled without writing a row, e.g. from Nightscout, must not)
        now = Date.now
        let activeTempTarget = TempTargetHBT.activeTarget(in: tempTargets, at: now)
        var hbtRow: TempTargetsSnapshot?
        if let activeTempTarget {
            hbtRow = await coreDataStorage.fetchTempTargetHBT(id: activeTempTarget.id)
        }
        let tempTargetHBT = TempTargetHBT.halfBasalTarget(row: hbtRow, activeTarget: activeTempTarget, at: now)
        print(
            "dynamicVariables: Time for fetchTempTargetHBT \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        let twoHoursArray = uniqueEvents
            .filter({ ($0.timestamp ?? Date()) >= Date.now.subtractingTimeInterval(.hours(2)) })
        var nrOfIndeces = twoHoursArray.count
        let totalAmount = twoHoursArray.compactMap({ each in each.tdd ?? 0 }).reduce(0, +)

        let temptargetActive = tempTargetHBT != nil
        if let tempTargetHBT {
            hbt_ = Decimal(tempTargetHBT)
        }

        var overridePercentage = Decimal(activeOverride?.percentage ?? 100)
        var unlimited = activeOverride?.indefinite ?? true
        var disableSMBs = activeOverride?.smbIsOff ?? false
        let overrideMaxIOB = activeOverride?.overrideMaxIOB ?? false
        let maxIOB = activeOverride?.maxIOB ?? preferences.maxIOB

        var name = ""
        if let activeOverride, activeOverride.isPreset,
           let overridePreset = await overrideStorage.getPresetName(for: activeOverride)
        {
            name = overridePreset
        }

        if nrOfIndeces == 0 {
            nrOfIndeces = 1
        }

        let average2hours = totalAmount / Decimal(nrOfIndeces)
        let average14 = uniqueEvents.averageDailyTDD
        let weighted_average = wp * average2hours + (1 - wp) * average14

        var duration: Decimal = 0
        var overrideTarget: Decimal = 0

        if let activeOverride {
            duration = activeOverride.duration ?? 0
            overrideTarget = activeOverride.target ?? 0
        } else {
            unlimited = true
            overridePercentage = 100
            disableSMBs = false
        }

        // Auto ISF
        var autoISFsettings: AutoISFsettings
        if let activeOverride, activeOverride.overrideAutoISF, let fetched = activeOverride.aisf
        {
            autoISFsettings = fetched
        } else {
            autoISFsettings = AutoISFsettings()
        }

        return DynamicVariables(
            average_total_data: average14,
            weightedAverage: weighted_average,
            weigthPercentage: wp,
            past2hoursAverage: average2hours,
            date: Date(),
            isEnabled: temptargetActive,
            presetActive: temptargetActive,
            overridePercentage: overridePercentage,
            useOverride: activeOverride != nil,
            duration: duration,
            unlimited: unlimited,
            hbt: hbt_,
            overrideTarget: overrideTarget,
            smbIsOff: disableSMBs,
            advancedSettings: activeOverride?.advancedSettings ?? false,
            isfAndCr: activeOverride?.isfAndCr ?? false,
            isf: activeOverride?.isf ?? true,
            cr: activeOverride?.cr ?? true,
            basal: activeOverride?.basal ?? true,
            smbIsAlwaysOff: activeOverride?.smbIsAlwaysOff ?? false,
            start: (activeOverride?.start ?? 0) as Decimal,
            end: (activeOverride?.end ?? 0) as Decimal,
            smbMinutes: activeOverride?.smbMinutes ?? smbMinutes,
            uamMinutes: activeOverride?.uamMinutes ?? uamMinutes,
            maxIOB: maxIOB as Decimal,
            overrideMaxIOB: overrideMaxIOB,
            preset: name,
            autoISFoverrides: autoISFsettings,
            aisfOverridden: activeOverride?.overrideAutoISF ?? false
        )
    }
}

/// Which half basal target applies: an HBT row only belongs to the temp target with its id.
enum TempTargetHBT {
    /// The temp target oref applies at `date` (same walk as oref0 targets.js): the newest started one,
    /// a cancel or an invalid range ends it.
    static func activeTarget(in targets: [TempTarget], at date: Date) -> TempTarget? {
        for target in targets.sorted(by: { $0.createdAt > $1.createdAt }) {
            let started = target.createdAt <= date
            if started, target.duration == 0 { return nil }
            guard let bottom = target.targetBottom, let top = target.targetTop, bottom != 0, top != 0 else { return nil }
            if started, date < target.createdAt.addingTimeInterval(.minutes(target.duration)) { return target }
        }
        return nil
    }

    /// The HBT of `row` when it is the % row of `activeTarget` and still within its duration; nil: no % temp target.
    static func halfBasalTarget(row: TempTargetsSnapshot?, activeTarget: TempTarget?, at date: Date) -> Double? {
        guard let row, let activeTarget, row.active, row.id == activeTarget.id,
              let start = row.startDate, let duration = row.duration, duration > 0,
              start <= date, date < start.addingTimeInterval(.minutes(duration))
        else { return nil }
        return row.hbt
    }
}
