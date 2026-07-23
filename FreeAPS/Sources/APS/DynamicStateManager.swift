import Foundation

protocol DynamicStateManager: Sendable {
    func dynamicVariables() async -> DynamicVariables
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

    func dynamicVariables() async -> DynamicVariables {
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

        // Temp Targets using slider
        now = Date.now
        let sliderArray = await coreDataStorage.fetchTempTargetsSlider()
        print(
            "dynamicVariables: Time for fetchTempTargetsSlider \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Overrides
        now = Date.now
        let activeOverride = await overrideStorage.fetchCurrentActiveOverride()
        print(
            "dynamicVariables: Time for fetchCurrentActiveOverride \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Temp Target
        now = Date.now
        let tempTargetsArray = await coreDataStorage.fetchTempTargets()
        print(
            "dynamicVariables: Time for fetchTempTargets \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Time adjusted average
        var time = uniqueEvents.first?.timestamp ?? .distantPast
        var data_ = [tddData(date: time, tdd: (uniqueEvents.first?.tdd ?? 0) as Decimal)]

        for a in uniqueEvents {
            if a.timestamp ?? .distantFuture <= time.subtractingTimeInterval(.hours(24)) {
                let b = tddData(
                    date: a.timestamp ?? .distantFuture,
                    tdd: (a.tdd ?? 0) as Decimal
                )
                data_.append(b)
                time = a.timestamp ?? .distantPast
            }
        }
        let total = data_.map(\.tdd).reduce(0, +)
        let indeces = data_.count

        let twoHoursArray = uniqueEvents
            .filter({ ($0.timestamp ?? Date()) >= Date.now.subtractingTimeInterval(.hours(2)) })
        var nrOfIndeces = twoHoursArray.count
        let totalAmount = twoHoursArray.compactMap({ each in each.tdd ?? 0 }).reduce(0, +)

        var temptargetActive = tempTargetsArray.first?.active ?? false
        let isPercentageEnabled = sliderArray.first?.enabled ?? false

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
        let average14 = total / Decimal(indeces)
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

        if temptargetActive {
            let duration_ = Int(truncating: tempTargetsArray.first?.duration as? NSNumber ?? 0)
            let hbt = tempTargetsArray.first?.hbt ?? Double(hbt_)

            let startDate = tempTargetsArray.first?.startDate ?? Date()
            let durationPlusStart = startDate.addingTimeInterval(.minutes(duration_))
            let dd = durationPlusStart.timeIntervalSinceNow.minutes

            if dd > 0.1 {
                hbt_ = Decimal(hbt)
                temptargetActive = true
            } else {
                temptargetActive = false
            }
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
            presetActive: isPercentageEnabled,
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
