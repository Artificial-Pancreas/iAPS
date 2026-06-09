import LoopKit
import SwiftUI

extension BasalProfileEditor {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner {
        @Injected() private var storage: FileStorage!
        @Injected() private var deviceManager: DeviceDataManager!
        @Injected() private var appCoordinator: AppCoordinator!

        private let coreDataStorage = CoreDataStorage()

        @Published var syncInProgress = false
        @Published var items: [Item] = []
        @Published var total: Decimal = 0.0
        @Published var saved = false
        @Published var allowDilution = false

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        private(set) var rateValues: [Decimal] = []

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        private static let profileFormatter = {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()

        override func subscribe() async {
            rateValues = readSupportedBasalRates() ?? stride(from: 5.0, to: 1001.0, by: 5.0)
                .map { ($0.decimal ?? .zero) / 100 }
            items = await retrieveProfile().map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.minutes * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.rate) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }
            calcTotal()
            allowDilution = await settingsManager.settings.allowDilution
        }

        private func currentProfile() -> [BasalProfileEntry] {
            items.map { item in
                let date = Date(timeIntervalSince1970: timeValues[item.timeIndex])
                return BasalProfileEntry(
                    start: Self.profileFormatter.string(from: date),
                    minutes: Int(date.timeIntervalSince1970 / 60),
                    rate: rateValues[item.rateIndex]
                )
            }
        }

        func calcTotal() {
            let profile = currentProfile()
            var profileWith24hours = profile.map(\.minutes)
            profileWith24hours.append(24 * 60)
            let pr2 = zip(profile, profileWith24hours.dropFirst())
            total = pr2.reduce(0) { $0 + (Decimal($1.1 - $1.0.minutes) / 60) * $1.0.rate }
        }

        func add() {
            var time = 0
            var rate = 0
            if let last = items.last {
                time = last.timeIndex + 1
                rate = last.rateIndex
            }

            let newItem = Item(rateIndex: rate, timeIndex: time)

            items.append(newItem)
            calcTotal()
        }

        func save() {
            Task {
                saved = false
                syncInProgress = true
                let profile = currentProfile()

                do {
                    try await saveProfile(profile)
                } catch {
                    // TODO: show the error in the UI?
                    debug(.default, "failed to save profile: \(error.localizedDescription)")
                }
                self.syncInProgress = false
                self.saved = true
            }
        }

        func validate() {
            let uniq = Array(Set(items))
            let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
            sorted.first?.timeIndex = 0
            items = sorted
        }

        private func retrieveProfile() async -> [BasalProfileEntry] {
            await storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
                ?? []
        }

        private func readSupportedBasalRates() -> [Decimal]? {
            deviceManager.supportedBasalRates()?.map { Decimal($0) }
        }

        private func readConcentration() -> Double {
            coreDataStorage.insulinConcentration().concentration
        }

        private func saveProfile(_ profile: [BasalProfileEntry]) async throws {
            let concentration = readConcentration()

            if let adjustedProfile = try await deviceManager.syncBasalRateSchedule(items: profile, concentration: concentration) {
                await storage.save(adjustedProfile, as: OpenAPS.Settings.basalProfile)
            } else {
                // no pump configured
                await storage.save(profile, as: OpenAPS.Settings.basalProfile)
            }
        }
    }
}
