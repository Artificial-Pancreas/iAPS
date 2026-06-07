import Foundation
import Swinject
import WatchConnectivity

protocol WatchManager {}

// TODO: integrating WatchConnectivity with async is tricky
// maybe worth converting to something like this eventually?
// https://github.com/ts95/WatchConnectivitySwift

actor BaseWatchManager: WatchManager, Injectable, LifetimeOwner {
    private let session: WCSession
    private let delegate: WatchSessionDelegate
    private var state = WatchState()

    // a copy of state - updated every time state is updated, for the pre-concurrency interop, namely the `garmin.stateRequet`
    nonisolated(unsafe) private var cachedStateData = Data()

    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var apsManager: APSManager!
    @Injected() private var storage: FileStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var garmin: GarminManager!
    @Injected() private var nightscout: NightscoutManager!
    @Injected() private var appCoordinator: AppCoordinator!

    private let overrideStorage = OverrideStorage()
    private let coreDataStorage = CoreDataStorage()

    private var settings: FreeAPSSettings!
    private var preferences: Preferences!
    private var pumpSettings: PumpSettings!
    private var suggestion: Suggestion!
    private var enactedSuggestion: Suggestion!

    let lifetime = Lifetime()

    init(resolver: Resolver, session: WCSession = .default) {
        self.session = session
        self.delegate = WatchSessionDelegate()
        injectServices(resolver)

        Task {
            await subscribe()
        }
    }

    private func subscribe() async {
        self.settings = await settingsManager.settings
        self.preferences = await settingsManager.preferences
        self.pumpSettings = await settingsManager.pumpSettings
        self.suggestion = await storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        self.enactedSuggestion = await storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)
        if WCSession.isSupported() {
            delegate.manager = self
            session.delegate = delegate
            session.activate()
        }

        observe(appCoordinator.glucoseHistoryUpdates) { me, _ in
            await me.configureState()
        }
        observe(appCoordinator.suggestions) { me, suggestion in
            await me.suggestionUpdated(suggestion)
            await me.configureState()
        }
        observe(appCoordinator.preferencesUpdates) { me, preferences in
            await me.preferencesUpdated(preferences)
            await me.configureState()
        }
        observe(appCoordinator.settingsUpdates) { me, settings in
            await me.settingsUpdated(settings)
            await me.configureState()
        }
//        observe(appCoordinator.pumpHistoryUpdates) { me, pumpHistory in
//            // TODO:
//        }
        observe(appCoordinator.pumpSettingsUpdates) { me, pumpSettings in
            await me.pumpSettingsUpdated(pumpSettings)
            await me.configureState()
        }
//        observe(appCoordinator.basalProfileUpdates) { me, basalProfile in
//            // TODO:
//        }
        observe(appCoordinator.tempTargetsUpdates) { me, _ in
            await me.configureState()
        }
//        observe(appCoordinator.carbHistoryUpdates) { me, carbs in
//            // TODO:
//        }
        observe(appCoordinator.enactedSuggestions) { me, enactedSuggestion in
            await me.enactedSuggestionUpdated(enactedSuggestion)
            await me.configureState()
        }
//        observe(appCoordinator.pumpBattery) { me, battery in
//            // TODO:
//        }
//        observe(appCoordinator.pumpReservoir) { me, reservoir in
//            // TODO:
//        }

        garmin.stateRequest = { [weak self] () -> Data in
            self?.cachedStateData ?? Data()
        }

        await configureState()
    }

    private func settingsUpdated(_ settings: FreeAPSSettings) {
        self.settings = settings
    }

    private func preferencesUpdated(_ preferences: Preferences) {
        self.preferences = preferences
    }

    private func pumpSettingsUpdated(_ pumpSettings: PumpSettings) {
        self.pumpSettings = pumpSettings
    }

    private func suggestionUpdated(_ suggestion: Suggestion) {
        self.suggestion = suggestion
    }

    private func enactedSuggestionUpdated(_ enactedSuggestion: Suggestion) {
        self.enactedSuggestion = enactedSuggestion
    }

    private func configureState() async {
        let reasons = coreDataStorage.fetchReason()

        if let reason = reasons {
            self.state.isf = (reason.isf ?? 15) as Decimal
            self.state.target = (reason.target ?? 100) as Decimal
            self.state.carbRatio = (reason.cr ?? 30) as Decimal
            self.state.minPredBG = (reason.minPredBG ?? 0) as Decimal
        }

        self.state.eventualGlucose = Decimal(suggestion?.eventualBG ?? 0)

        let readings = self.coreDataStorage.fetchGlucose(interval: DateFilter.twoHours.startDate)
        let glucoseValues = self.glucoseText(readings)
        self.state.glucose = glucoseValues.glucose
        self.state.trend = glucoseValues.trend
        self.state.delta = glucoseValues.delta
        self.state.trendRaw = self.convertTrendToDirectionText(trend: glucoseValues.trend)
        self.state.glucoseDate = readings.first?.date ?? .distantPast
        self.state.glucoseDateInterval = self.state.glucoseDate.map {
            guard $0.timeIntervalSince1970 > 0 else { return 0 }
            return UInt64($0.timeIntervalSince1970)
        }
        self.state.lastLoopDate = enactedSuggestion?.recieved == true ? enactedSuggestion?.deliverAt : self
            .appCoordinator.lastLoopDate.value
        self.state.lastLoopDateInterval = self.state.lastLoopDate.map {
            guard $0.timeIntervalSince1970 > 0 else { return 0 }
            return UInt64($0.timeIntervalSince1970)
        }
        self.state.bolusIncrement = preferences.bolusIncrement
        self.state.maxCOB = preferences.maxCOB
        self.state.maxBolus = pumpSettings.maxBolus
        self.state.carbsRequired = suggestion?.carbsReq

        let useNewCalc = settings.useCalc
        self.state.useNewCalc = useNewCalc

        self.state.iob = suggestion?.iob
        self.state.cob = suggestion?.cob
        let currentTarget = await self.tempTargetsStorage.current()
        self.state.tempTargets = await self.tempTargetsStorage.presets()
            .map { target -> TempTargetWatchPreset in
                let untilDate = currentTarget.flatMap { currentTarget -> Date? in
                    guard currentTarget.id == target.id else { return nil }
                    let date = currentTarget.createdAt.addingTimeInterval(TimeInterval(currentTarget.duration * 60))
                    return date > Date() ? date : nil
                }
                return TempTargetWatchPreset(
                    name: target.displayName,
                    id: target.id,
                    description: self.descriptionForTarget(target),
                    until: untilDate
                )
            }

        self.state.overrides = overrideStorage.fetchProfiles()
            .map { preset -> OverridePresets_ in
                let untilDate = overrideStorage.fetchLatestOverride().first.flatMap { currentOverride -> Date? in
                    guard currentOverride.id == preset.id, currentOverride.enabled else { return nil }

                    let duration = Double(truncating: currentOverride.duration ?? 0)
                    let overrideDate: Date = currentOverride.date ?? Date.now

                    let date = duration == 0 ? Date.distantFuture : overrideDate.addingTimeInterval(duration * 60)
                    return date > Date.now ? date : nil
                }

                return OverridePresets_(
                    name: preset.name ?? "",
                    id: preset.id ?? "",
                    until: untilDate,
                    description: self.description(preset)
                )
            }
        // Is there an active override but no preset?
        let currentButNoOverrideNotPreset = self.state.overrides.filter({ $0.until != nil }).first
        if let last = overrideStorage.fetchLatestOverride().first, last.enabled, currentButNoOverrideNotPreset == nil {
            let duration = Double(truncating: last.duration ?? 0)
            let overrideDate: Date = last.date ?? Date.now
            let date_ = duration == 0 ? Date.distantFuture : overrideDate.addingTimeInterval(duration * 60)
            let date = date_ > Date.now ? date_ : nil

            self.state.overrides
                .append(OverridePresets_(name: "custom", id: last.id ?? "", until: date, description: self.description(last)))
        }

        self.state.bolusAfterCarbs = !settings.skipBolusScreenAfterCarbs
        self.state.displayOnWatch = settings.displayOnWatch
        self.state.displayFatAndProteinOnWatch = settings.displayFatAndProteinOnWatch
        self.state.confirmBolusFaster = settings.confirmBolusFaster
        self.state.profilesOrTempTargets = settings.profilesOrTempTargets

        let eBG = self.eventualBGString(suggestion: suggestion)
        self.state.eventualBG = eBG.map { "⇢ " + $0 }
        self.state.eventualBGRaw = eBG

        let overrideArray = overrideStorage.fetchLatestOverride()

        if overrideArray.first?.enabled ?? false {
            let percentString = "\((overrideArray.first?.percentage ?? 100).formatted(.number)) %"
            self.state.override = percentString
        } else {
            self.state.override = "100 %"
        }

        if useNewCalc {
            self.state.deltaBG = self.getDeltaBG(readings)
            self.state.bolusRecommended = self.roundBolus(
                max(
                    self.roundBolus(
                        max(self.newBolusCalc(delta: readings), 0),
                    ),
                    0
                )
            )
        } else {
            self.state.bolusRecommended = 0
        }

        // cache the serialized state to be used by `garmin.stateRequet`
        self.cachedStateData = (try? JSONEncoder().encode(state)) ?? Data()

        self.sendState()
    }

    private func getDeltaBG(_ glucose: [Readings]) -> Decimal? {
        guard let lastGlucose = glucose.first, glucose.count >= 4 else { return nil }
        return Decimal(lastGlucose.glucose + glucose[1].glucose) / 2 -
            (Decimal(glucose[3].glucose + glucose[2].glucose) / 2)
    }

    private func roundBolus(_ amount: Decimal) -> Decimal {
        // Account for increments (don't use the APSManager function as that gets too slow)
        let bolusIncrement = preferences.bolusIncrement
        return Decimal(round(Double(amount / bolusIncrement))) * bolusIncrement
    }

    fileprivate func sendState() {
        let data = cachedStateData
        guard !data.isEmpty else { return }

        garmin.sendState(data)

        guard session.isReachable else { return }
        session.sendMessageData(data, replyHandler: nil) { error in
            warning(.service, "Cannot send message to watch", error: error)
        }
    }

    private func glucoseText(_ glucose: [Readings]) -> (glucose: String, trend: String, delta: String) {
        guard !glucose.isEmpty else { return ("--", "--", "--") }

        let glucoseValue = glucose.first?.glucose ?? 0

        let delta = glucose.count >= 2 ? glucoseValue - glucose[1].glucose : nil

        let units = settings.units
        let glucoseText = glucoseFormatter
            .string(from: (
                units == .mmolL ? Decimal(glucoseValue).asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!

        let directionText = glucose.first?.direction ?? "↔︎"
        let deltaText = delta
            .map {
                Self.deltaFormatter
                    .string(from: (
                        units == .mmolL ? Decimal($0).asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return (glucoseText, directionText, deltaText)
    }

    private func descriptionForTarget(_ target: TempTarget) -> String {
        let units = settings.units

        var low = target.targetBottom
        var high = target.targetTop
        if units == .mmolL {
            low = low?.asMmolL
            high = high?.asMmolL
        }

        let description =
            "\(Self.targetFormatter.string(from: (low ?? 0) as NSNumber)!) - \(Self.targetFormatter.string(from: (high ?? 0) as NSNumber)!)" +
            " for \(Self.targetFormatter.string(from: target.duration as NSNumber)!) min"

        return description
    }

    private func eventualBGString(suggestion: Suggestion?) -> String? {
        guard let eventualBG = suggestion?.eventualBG else {
            return nil
        }
        let units = settings.units
        return Self.eventualFormatter.string(
            from: (units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
        )!
    }

    private func convertTrendToDirectionText(trend: String) -> String {
        switch trend {
        case "↑↑↑":
            return Direction.tripleUp.rawValue
        case "↑↑":
            return Direction.doubleUp.rawValue
        case "↑":
            return Direction.singleUp.rawValue
        case "↗︎":
            return Direction.fortyFiveUp.rawValue
        case "→":
            return Direction.flat.rawValue
        case "↘︎":
            return Direction.fortyFiveDown.rawValue
        case "↓":
            return Direction.singleDown.rawValue
        case "↓↓↓":
            return Direction.tripleDown.rawValue
        case "↓↓":
            return Direction.doubleDown.rawValue
        default:
            return Direction.notComputable.rawValue
        }
    }

    private func newBolusCalc(delta: [Readings]) -> Decimal {
        var conversion: Decimal = 1
        // Settings etc
        if settings.units == .mmolL {
            conversion = 0.0555
        }
        let useEventual = settings.eventualBG
        let useMinPredBG = settings.minumimPrediction
        let isf = state.isf ?? 15
        let target = state.target ?? 100
        let carbRatio = state.carbRatio ?? 30
        let deltaBG = getDeltaBG(delta) ?? 0
        let eventualGlucose = (state.eventualGlucose ?? 0) * conversion

        let currentGlucose = delta.first != nil ? (delta.first?.glucose ?? 0) : 0
        let fraction = settings.overrideFactor
        let minPredBG = state.minPredBG ?? 0

        var threshold = preferences.threshold_setting
        threshold = max(target - 0.5 * (target - 40 * conversion), threshold * conversion)
        let bg = Decimal(delta.first?.glucose ?? 0) * conversion

        var targetDifferenceInsulin: Decimal = 0

        var insulinCalculated: Decimal = 0
        var insulin: Decimal = 0 // Oref0
        var wholeCalc: Decimal = 0

        // Use either the eventual glucose prediction or just the Swift code
        if useEventual {
            if eventualGlucose > target {
                // Use Oref0 predictions{
                insulin = (eventualGlucose - target) / isf
            } else { insulin = 0 }
        } else {
            let targetDifference = bg - target
            targetDifferenceInsulin = isf == 0 ? 0 : targetDifference / isf
        }

        // more or less insulin because of bg trend in the last 15 minutes
        let fifteenMinInsulin = isf == 0 ? 0 : (deltaBG * conversion) / isf

        let cob = state.cob ?? 0
        let iob = state.iob ?? 0
        let maxBolus = pumpSettings.maxBolus

        // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
        let wholeCobInsulin = carbRatio != 0 ? cob / carbRatio : 0

        // determine how much the calculator reduces/ increases the bolus because of IOB
        let iobInsulinReduction = (-1) * iob

        // adding everything together
        if deltaBG != 0 {
            wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin + fifteenMinInsulin)
        } else {
            if currentGlucose == 0 {
                wholeCalc = (iobInsulinReduction + wholeCobInsulin)
            } else {
                wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin)
            }
        }

        // apply custom factor at the end of the calculations
        insulinCalculated = !useEventual ? wholeCalc * fraction : insulin * fraction

        // A blend of Oref0 predictions and the Swift calculator {
        if useMinPredBG, minPredBG < threshold {
            if useEventual { insulinCalculated = 0 }
            return 0
        }

        // Account for increments (Don't use the apsManager function as that gets much too slow)
        insulinCalculated = roundBolus(insulinCalculated)
        // 0 up to maxBolus
        insulinCalculated = min(max(insulinCalculated, 0), maxBolus)
        return insulinCalculated
    }

    private func description(_ preset: OverridePresets) -> String {
        let rawtarget = (preset.target ?? 0) as Decimal

        let targetValue = settings.units == .mmolL ? rawtarget.asMmolL : rawtarget
        let target: String = rawtarget > 6 ? glucoseFormatter.string(from: targetValue as NSNumber) ?? "" : ""

        let percentage = preset.percentage != 100 ? preset.percentage.formatted() + "%" : ""
        let string = (preset.target ?? 0) as Decimal > 6 && !percentage.isEmpty ? target + " " + settings.units
            .rawValue + ", " + percentage : target + percentage
        return string
    }

    private func description(_ override: Override) -> String {
        let rawtarget = (override.target ?? 0) as Decimal

        let targetValue = settings.units == .mmolL ? rawtarget.asMmolL : rawtarget
        let target: String = rawtarget > 6 ? glucoseFormatter.string(from: targetValue as NSNumber) ?? "" : ""

        let percentage = override
            .percentage != 100 ? (Self.formatter.string(from: override.percentage as NSNumber) ?? "") + "%" : ""
        let string = (override.target ?? 0) as Decimal > 6 && !percentage.isEmpty ? target + " " + settings.units
            .rawValue + ", " + percentage : target + percentage
        return string
    }

    private static let formatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private var glucoseFormatter: NumberFormatter {
        switch settings.units {
        case .mmolL: return Self.glucoseFormatterMmol
        case .mgdL: return Self.glucoseFormatterMgdl
        }
    }

    private static let glucoseFormatterMmol = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let glucoseFormatterMgdl = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let eventualFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let deltaFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }()

    private static let targetFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private extension BaseWatchManager {
    func handleMessage(_ message: WatchMessage) async -> WatchReply {
        debug(.service, "WCSession got message: \(message)")

        let settings = await settingsManager.settings

        if let carbs = message.carbs,
           let fat = message.fat,
           let protein = message.protein,
           carbs > 0 || fat > 0 || protein > 0
        {
            await carbsStorage.storeCarbs(
                [CarbsEntry(
                    id: UUID().uuidString,
                    createdAt: Date(),
                    actualDate: nil,
                    carbs: Decimal(carbs),
                    fat: Decimal(fat),
                    protein: Decimal(protein),
                    fiber: nil,
                    note: nil,
                    enteredBy: CarbsEntry.watch,
                    isFPU: false
                )]
            )

            if settings.skipBolusScreenAfterCarbs {
                Task {
                    _ = await apsManager.determineBasal(temporaryCarbs: nil)
                }
                return .confirmed
            } else {
                _ = await apsManager.determineBasal(temporaryCarbs: nil)
                return .confirmed
            }
        }

        if let tempTargetID = message.tempTarget {
            if var preset = await tempTargetsStorage.presets().first(where: { $0.id == tempTargetID }) {
                preset.createdAt = Date()
                await tempTargetsStorage.storeTempTargets([preset])
                return .confirmed
            } else if tempTargetID == "cancel" {
                let entry = TempTarget(
                    name: TempTarget.cancel,
                    createdAt: Date(),
                    targetTop: 0,
                    targetBottom: 0,
                    duration: 0,
                    enteredBy: TempTarget.manual,
                    reason: TempTarget.cancel
                )
                await tempTargetsStorage.storeTempTargets([entry])
                return .confirmed
            }
        }

        if let overrideID = message.override {
            if let preset = overrideStorage.fetchProfiles().first(where: { $0.id == overrideID }) {
                preset.date = Date.now

                // Cancel eventual current active override first
                if let activeOveride = overrideStorage.fetchLatestOverride().first, activeOveride.enabled {
                    let name = overrideStorage.isPresetName()

                    if let duration = overrideStorage.cancelProfile() {
                        let nsString = name ?? activeOveride.percentage.formatted()
                        await nightscout.editOverride(nsString, duration, activeOveride.date ?? Date())
                    }
                }
                // Activate the new override and uplad the new ovderride to NS. Some duplicate code now.
                overrideStorage.overrideFromPreset(preset)
                await nightscout.uploadOverride(
                    preset.name ?? "",
                    Double(truncating: preset.duration ?? 0),
                    overrideStorage.fetchLatestOverride().first?.date ?? Date.now
                )
                await configureState()
                return .confirmed
            } else if overrideID == "cancel" {
                if let activeOveride = overrideStorage.fetchLatestOverride().first, activeOveride.enabled {
                    let presetName = overrideStorage.isPresetName()
                    let nsString = presetName ?? activeOveride.percentage.formatted()

                    if let duration = overrideStorage.cancelProfile() {
                        await nightscout.editOverride(nsString, duration, activeOveride.date ?? Date.now)
                        await configureState()
                        return .confirmed
                    }
                }
                return .denied
            }
        }

        if let bolus = message.bolus, bolus > 0 {
            Task {
                _ = await apsManager.enactBolus(amount: bolus, isSMB: false)
            }
            return .confirmed
        }

        return .denied
    }
}

final class WatchSessionDelegate: NSObject {
    weak var manager: BaseWatchManager?
}

extension WatchSessionDelegate: WCSessionDelegate {
    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_: WCSession) {}

    func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error _: Error?) {
        debug(.service, "WCSession is activated: \(state == .activated)")
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        debug(.service, "WCSession got message: \(message)")
        guard (message["stateRequest"] as? Bool) ?? false else { return }
        guard let manager else { return }
        Task {
            await manager.sendState()
        }
    }

    private struct WatchReplyHandler: @unchecked Sendable {
        private let handler: ([String: Any]) -> Void

        init(_ handler: @escaping ([String: Any]) -> Void) {
            self.handler = handler
        }

        func callAsFunction(_ reply: WatchReply) {
            handler(reply.dict)
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let manager else { return }
        let msg = WatchMessage(message)
        let safeReplyHandler = WatchReplyHandler(replyHandler)
        Task {
            let reply = await manager.handleMessage(msg)
            safeReplyHandler(reply)
        }
    }

    func session(_: WCSession, didReceiveMessageData _: Data) {}

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        guard let manager else { return }
        Task {
            await manager.sendState()
        }
    }
}
