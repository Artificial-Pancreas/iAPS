import Foundation
import SwiftDate
import Swinject

protocol CarbsStorage: Sendable {
    func storeCarbs(_ carbs: [CarbsEntry]) async
    func syncDate() async -> Date
    func recent() async -> [CarbsEntry]
    func nightscoutTretmentsNotUploaded() async -> [NigtscoutTreatment]
    func deleteCarbsAndFPUs(at date: Date) async
}

actor BaseCarbsStorage: CarbsStorage, Injectable {
//    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var appCoordinator: AppCoordinator!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeCarbs(_ entries: [CarbsEntry]) async {
        let file = OpenAPS.Monitor.carbHistory
        var uniqEvents: [CarbsEntry] = []

        let fat = entries.last?.fat ?? 0
        let protein = entries.last?.protein ?? 0
        let creationDate = entries.last?.createdAt ?? Date.now

        let settings = await settingsManager.settings

        if fat > 0 || protein > 0 {
            // -------------------------- FPU--------------------------------------
            let interval = settings.minuteInterval // Interval between carbs
            let timeCap = settings.timeCap // Max Duration
            let adjustment = settings.individualAdjustmentFactor
            let delay = settings.delay // Tme before first future carb entry
            let kcal = protein * 4 + fat * 9
            let carbEquivalents = (kcal / 10) * adjustment
            let fpus = carbEquivalents / 10
            // Duration in hours used for extended boluses with Warsaw Method. Here used for total duration of the computed carb equivalents instead, excluding the configurable delay.
            var computedDuration = 0
            switch fpus {
            case ..<2:
                computedDuration = 3
            case 2 ..< 3:
                computedDuration = 4
            case 3 ..< 4:
                computedDuration = 5
            default:
                computedDuration = timeCap
            }
            // Size of each created carb equivalent if 60 minutes interval
            var equivalent: Decimal = carbEquivalents / Decimal(computedDuration)
            // Adjust for interval setting other than 60 minutes
            equivalent /= Decimal(60 / interval)
            // Round to 1 fraction digit
            equivalent = Decimal(round(Double(equivalent * 10)) / 10)
            // Round up to 1 or done to 0 as oref0 only accepts carbs >= 1
            equivalent = equivalent > IAPSconfig.minimumCarbEquivalent ? max(equivalent, 1) : 0
            // Number of equivalents
            var numberOfEquivalents = equivalent > 0 ? carbEquivalents / equivalent : 0
            // Only use delay in first loop
            var firstIndex = true
            // New date for each carb equivalent
            var useDate = entries.last?.actualDate ?? Date()
            // Group and Identify all FPUs together
            // Create an array of all future carb equivalents.
            var futureCarbArray = [CarbsEntry]()
            while carbEquivalents > 0, numberOfEquivalents > 0 {
                if firstIndex {
                    useDate = useDate.addingTimeInterval(delay.minutes.timeInterval)
                    firstIndex = false
                } else { useDate = useDate.addingTimeInterval(interval.minutes.timeInterval) }

                let eachCarbEntry = CarbsEntry(
                    id: UUID().uuidString, createdAt: creationDate, actualDate: useDate,
                    carbs: equivalent, fat: 0, protein: 0, fiber: nil, note: nil,
                    enteredBy: CarbsEntry.manual, isFPU: true
                )
                futureCarbArray.append(eachCarbEntry)
                numberOfEquivalents -= 1
            }
            // Save the array
            if carbEquivalents > 0 {
                uniqEvents = await self.storage.appendAndModify(futureCarbArray, to: file, uniqBy: \.id) {
                    $0
                        .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                        .sorted { $0.createdAt > $1.createdAt }
                }
            }
        } // ------------------------- END OF FPU ----------------------------------------
        // Store the actual (normal) carbs
        if let entry = entries.last {
            // uniqEvents = []
            let onlyCarbs = CarbsEntry(
                id: entry.id ?? "",
                createdAt: creationDate,
                actualDate: entry.actualDate ?? entry.createdAt,
                carbs: entry.carbs,
                fat: fat,
                protein: protein, fiber: entry.fiber,
                note: entry.note,
                enteredBy: entry.enteredBy ?? "",
                isFPU: false,
                micronutrient: entry.micronutrient
            )

            // If fetched en masse from NS
            if entries.filter({ $0.carbs > 0 }).count > 1 {
                uniqEvents = await self.storage.appendAndModify(entries, to: file, uniqBy: \.createdAt) {
                    $0
                        .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                        .sorted { $0.createdAt > $1.createdAt }
                }
            } else {
                uniqEvents = await self.storage.appendAndModify([onlyCarbs], to: file, uniqBy: \.id) {
                    $0
                        .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                        .sorted { $0.createdAt > $1.createdAt }
                }
            }
        }

        appCoordinator.carbHistoryUpdates.send(uniqEvents)
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recent() async -> [CarbsEntry] {
        await storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self)?.reversed() ?? []
    }

    func deleteCarbsAndFPUs(at date: Date) async {
        let allValues = await storage.modify(file: OpenAPS.Monitor.carbHistory, as: CarbsEntry.self) {
            $0.filter { $0.createdAt != date }
//            $0.removeAll(where: { $0.createdAt == date })
        }
        appCoordinator.carbHistoryUpdates.send(allValues)
    }

    func nightscoutTretmentsNotUploaded() async -> [NigtscoutTreatment] {
        let uploaded = await storage.retrieve(OpenAPS.Nightscout.uploadedCarbs, as: [NigtscoutTreatment].self) ?? []

        let eventsManual = await recent()
            .filter {
                ($0.enteredBy == CarbsEntry.manual || $0.enteredBy == CarbsEntry.remote || $0.enteredBy == CarbsEntry.shortcut) &&
                    $0.carbs > 0 }
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsCarbCorrection,
                createdAt: $0.actualDate ?? .distantPast,
                enteredBy: $0.enteredBy ?? CarbsEntry.manual,
                bolus: nil,
                insulin: nil,
                carbs: $0.carbs,
                fat: nil,
                protein: nil,
                foodType: $0.note,
                targetTop: nil,
                targetBottom: nil,
                id: $0.id,
                fpuID: nil,
                creation_date: $0.createdAt
            )
        }
        return Array(Set(treatments).subtracting(Set(uploaded)))
    }
}
