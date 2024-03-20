import Algorithms
import Combine
import Contacts
import Foundation
import LoopKit
import LoopKitUI
import MinimedKit
import MockKit
import OmniBLE
import OmniKit
import ShareClient
import SwiftDate
import Swinject
import UserNotifications

protocol ContactTrickManager {
    func updateContacts(contacts: [ContactTrickEntry], completion: @escaping (Result<Void, Error>) -> Void)
}

private let accessLock = NSRecursiveLock(label: "BaseContactTrickManager.accessLock")

final class BaseContactTrickManager: NSObject, ContactTrickManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseContactTrickManager.processQueue")
    private var state = ContactTrickState()
    private let contactStore = CNContactStore()
    private var workItem: DispatchWorkItem?

    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var apsManager: APSManager!
    @Injected() private var storage: FileStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!

    private var contacts: [ContactTrickEntry] = []

    let coreDataStorage = CoreDataStorage()

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)

        contacts = storage.retrieve(OpenAPS.Settings.contactTrick, as: [ContactTrickEntry].self)
            ?? [ContactTrickEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.contactTrick))
            ?? []

        broadcaster.register(GlucoseObserver.self, observer: self)
        broadcaster.register(SuggestionObserver.self, observer: self)
        broadcaster.register(SettingsObserver.self, observer: self)
        broadcaster.register(PumpHistoryObserver.self, observer: self)
        broadcaster.register(PumpSettingsObserver.self, observer: self)
        broadcaster.register(BasalProfileObserver.self, observer: self)
        broadcaster.register(TempTargetsObserver.self, observer: self)
        broadcaster.register(CarbsObserver.self, observer: self)
        broadcaster.register(EnactedSuggestionObserver.self, observer: self)
        broadcaster.register(PumpBatteryObserver.self, observer: self)
        broadcaster.register(PumpReservoirObserver.self, observer: self)

        configureState()
    }

    func updateContacts(contacts: [ContactTrickEntry], completion: @escaping (Result<Void, Error>) -> Void) {
        print("update contacts: \(contacts)")
        processQueue.async {
            self.contacts = contacts
            self.renderContacts()
            completion(.success(()))
        }
    }

    private func configureState() {
        processQueue.async {
            let overrideStorage = OverrideStorage()
            let readings = self.coreDataStorage.fetchGlucose(interval: DateFilter().twoHours)
            let glucoseValues = self.glucoseText(readings)
            self.state.glucose = glucoseValues.glucose
            self.state.trend = glucoseValues.trend
            self.state.delta = glucoseValues.delta
            self.state.glucoseDate = readings.first?.date ?? .distantPast
            self.state.lastLoopDate = self.enactedSuggestion?.recieved == true ? self.enactedSuggestion?.deliverAt : self
                .apsManager.lastLoopDate
            self.state.carbsRequired = self.suggestion?.carbsReq

            var insulinRequired = self.suggestion?.insulinReq ?? 0

            var double: Decimal = 2
            if self.suggestion?.manualBolusErrorString == 0 {
                insulinRequired = self.suggestion?.insulinForManualBolus ?? 0
                double = 1
            }

            self.state.useNewCalc = self.settingsManager.settings.useCalc

            if !(self.state.useNewCalc ?? false) {
                self.state.bolusRecommended = self.apsManager
                    .roundBolus(amount: max(
                        insulinRequired * (self.settingsManager.settings.insulinReqPercentage / 100) * double,
                        0
                    ))
            } else {
                let recommended = self.newBolusCalc(delta: readings, suggestion: self.suggestion)
                self.state.bolusRecommended = self.apsManager
                    .roundBolus(amount: max(recommended, 0))
            }

            self.state.iob = self.suggestion?.iob
            self.state.maxIOB = self.settingsManager.preferences.maxIOB
            self.state.cob = self.suggestion?.cob
            self.state.tempTargets = self.tempTargetsStorage.presets()
                .map { target -> TempTargetContactPreset in
                    let untilDate = self.tempTargetsStorage.current().flatMap { currentTarget -> Date? in
                        guard currentTarget.id == target.id else { return nil }
                        let date = currentTarget.createdAt.addingTimeInterval(TimeInterval(currentTarget.duration * 60))
                        return date > Date() ? date : nil
                    }
                    return TempTargetContactPreset(
                        name: target.displayName,
                        id: target.id,
                        description: self.descriptionForTarget(target),
                        until: untilDate
                    )
                }

            self.state.profilesOrTempTargets = self.settingsManager.settings.profilesOrTempTargets

            let eBG = self.eventualBGString()
            self.state.eventualBG = eBG.map { "⇢ " + $0 }
            self.state.eventualBGRaw = eBG

            self.state.isf = self.suggestion?.isf

            let overrideArray = overrideStorage.fetchLatestOverride()

            if overrideArray.first?.enabled ?? false {
                let percentString = "\((overrideArray.first?.percentage ?? 100).formatted(.number)) %"
                self.state.override = percentString
            } else {
                self.state.override = "100 %"
            }

            self.renderContacts()
        }
    }

    private func renderContacts() {
        contacts.forEach { renderContact($0) }
        workItem = DispatchWorkItem(block: {
            print("in updateContact, no updates received for more than 5 minutes")
            self.renderContacts()
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 5 * 60 + 15, execute: workItem!)
    }

    private func renderContact(_ entry: ContactTrickEntry) {
        guard let contactId = entry.contactId, entry.enabled else {
            return
        }

        let keysToFetch = [CNContactImageDataKey] as [CNKeyDescriptor]

        let contact: CNContact
        do {
            contact = try contactStore.unifiedContact(withIdentifier: contactId, keysToFetch: keysToFetch)
        } catch {
            print("in updateContact, an error has been thrown while fetching the selected contact")
            return
        }

        guard let mutableContact = contact.mutableCopy() as? CNMutableContact else {
            return
        }

        mutableContact.imageData = ContactPicture.getImage(
            contact: entry,
            state: state
        ).pngData()

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutableContact)
        do {
            try contactStore.execute(saveRequest)
        } catch {
            print("in updateContact, failed to update the contact")
        }
    }

    // copy-pastes from the BaseWatchManager
    private func newBolusCalc(delta: [Readings], suggestion _: Suggestion?) -> Decimal {
        var conversion: Decimal = 1
        // Settings
        if settingsManager.settings.units == .mmolL {
            conversion = 0.0555
        }
        let isf = state.isf ?? 0
        let target = suggestion?.current_target ?? 0
        let carbratio = suggestion?.carbRatio ?? 0
        let bg = delta.first?.glucose ?? 0
        let cob = state.cob ?? 0
        let iob = state.iob ?? 0
        let useFattyMealCorrectionFactor = settingsManager.settings.fattyMeals
        let fattyMealFactor = settingsManager.settings.fattyMealFactor
        let maxBolus = settingsManager.pumpSettings.maxBolus
        var insulinCalculated: Decimal = 0
        // insulin needed for the current blood glucose
        let targetDifference = (Decimal(bg) - target) * conversion
        let targetDifferenceInsulin = targetDifference / isf
        // more or less insulin because of bg trend in the last 15 minutes
        var bgDelta: Int = 0
        if delta.count >= 3 {
            bgDelta = Int((delta.first?.glucose ?? 0) - delta[2].glucose)
        }
        let fifteenMinInsulin = (Decimal(bgDelta) * conversion) / isf
        // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
        let wholeCobInsulin = cob / carbratio
        // determine how much the calculator reduces/ increases the bolus because of IOB
        let iobInsulinReduction = (-1) * iob
        // adding everything together
        // add a calc for the case that no fifteenMinInsulin is available
        var wholeCalc: Decimal = 0
        if bgDelta != 0 {
            wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin + fifteenMinInsulin)
        } else {
            // add (rare) case that no glucose value is available -> maybe display warning?
            // if no bg is available, ?? sets its value to 0
            if bg == 0 {
                wholeCalc = (iobInsulinReduction + wholeCobInsulin)
            } else {
                wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin)
            }
        }
        // apply custom factor at the end of the calculations
        let result = wholeCalc * settingsManager.settings.overrideFactor
        // apply custom factor if fatty meal toggle in bolus calc config settings is on and the box for fatty meals is checked (in RootView)
        if useFattyMealCorrectionFactor {
            insulinCalculated = result * fattyMealFactor
        } else {
            insulinCalculated = result
        }
        // Not 0 or over maxBolus
        insulinCalculated = max(min(insulinCalculated, maxBolus), 0)
        return insulinCalculated
    }

    private func glucoseText(_ glucose: [Readings]) -> (glucose: String, trend: String, delta: String) {
        let glucoseValue = glucose.first?.glucose ?? 0

        guard !glucose.isEmpty else { return ("--", "--", "--") }

        let delta = glucose.count >= 2 ? glucoseValue - glucose[1].glucose : nil

        let units = settingsManager.settings.units
        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? Decimal(glucoseValue).asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!

        let directionText = glucose.first?.direction ?? "↔︎"
        let deltaText = delta
            .map {
                self.deltaFormatter
                    .string(from: Double(
                        units == .mmolL ? Decimal($0).asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return (glucoseText, directionText, deltaText)
    }

    private func descriptionForTarget(_ target: TempTarget) -> String {
        let units = settingsManager.settings.units

        var low = target.targetBottom
        var high = target.targetTop
        if units == .mmolL {
            low = low?.asMmolL
            high = high?.asMmolL
        }

        let description =
            "\(targetFormatter.string(from: (low ?? 0) as NSNumber)!) - \(targetFormatter.string(from: (high ?? 0) as NSNumber)!)" +
            " for \(targetFormatter.string(from: target.duration as NSNumber)!) min"

        return description
    }

    private func eventualBGString() -> String? {
        guard let eventualBG = suggestion?.eventualBG else {
            return nil
        }
        let units = settingsManager.settings.units
        return eventualFormatter.string(
            from: (units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
        )!
    }

    private func description(_ preset: OverridePresets) -> String {
        let rawtarget = (preset.target ?? 0) as Decimal

        let targetValue = settingsManager.settings.units == .mmolL ? rawtarget.asMmolL : rawtarget
        let target: String = rawtarget > 6 ? glucoseFormatter.string(from: targetValue as NSNumber) ?? "" : ""

        let percentage = preset.percentage != 100 ? preset.percentage.formatted() + "%" : ""
        let string = (preset.target ?? 0) as Decimal > 6 && !percentage.isEmpty ? target + " " + settingsManager.settings.units
            .rawValue + ", " + percentage : target + percentage
        return string
    }

    private func description(_ override: Override) -> String {
        let rawtarget = (override.target ?? 0) as Decimal

        let targetValue = settingsManager.settings.units == .mmolL ? rawtarget.asMmolL : rawtarget
        let target: String = rawtarget > 6 ? glucoseFormatter.string(from: targetValue as NSNumber) ?? "" : ""

        let percentage = override.percentage != 100 ? override.percentage.formatted() + "%" : ""
        let string = (override.target ?? 0) as Decimal > 6 && !percentage.isEmpty ? target + " " + settingsManager.settings.units
            .rawValue + ", " + percentage : target + percentage
        return string
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var eventualFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }

    private var targetFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var suggestion: Suggestion? {
        storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
    }

    private var enactedSuggestion: Suggestion? {
        storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)
    }
}

extension BaseContactTrickManager:
    GlucoseObserver,
    SuggestionObserver,
    SettingsObserver,
    PumpHistoryObserver,
    PumpSettingsObserver,
    BasalProfileObserver,
    TempTargetsObserver,
    CarbsObserver,
    EnactedSuggestionObserver,
    PumpBatteryObserver,
    PumpReservoirObserver
{
    func glucoseDidUpdate(_: [BloodGlucose]) {
        configureState()
    }

    func suggestionDidUpdate(_: Suggestion) {
        configureState()
    }

    func settingsDidChange(_: FreeAPSSettings) {
        configureState()
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        // TODO:
    }

    func pumpSettingsDidChange(_: PumpSettings) {
        configureState()
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) {
        // TODO:
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        configureState()
    }

    func carbsDidUpdate(_: [CarbsEntry]) {
        // TODO:
    }

    func enactedSuggestionDidUpdate(_: Suggestion) {
        configureState()
    }

    func pumpBatteryDidChange(_: Battery) {
        // TODO:
    }

    func pumpReservoirDidChange(_: Decimal) {
        // TODO:
    }
}
