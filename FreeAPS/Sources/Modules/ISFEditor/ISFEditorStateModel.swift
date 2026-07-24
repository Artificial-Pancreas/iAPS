import SwiftUI
import Swinject

extension ISFEditor {
    final class StateModel: BaseStateModel<Provider>, UIBindingOwner {
        @Injected() private var isfScheduleStorage: IsfScheduleStorage!
        private let coreDataStorage = CoreDataStorage()
        let uiBindings = UIBindings()

        @Published var items: [Item] = []
        @Published var autotune: Profile?

        let timeValues = stride(from: 0.0, to: TimeInterval.hours(24), by: TimeInterval.minutes(30)).map { $0 }

        override init(resolver: Resolver) {
            super.init(resolver: resolver)
        }

        var rateValues: [Decimal] {
            switch units {
            case .mgdL:
                return stride(from: 9, to: 540.01, by: 1.0).map { Decimal($0) }
            case .mmolL:
                return stride(from: 1.0, to: 301.0, by: 1.0).map { Decimal($0) / 10 }
            }
        }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() async {
            let isfSchedule = appCoordinator.isfSchedule.value
            units = isfSchedule.units
            items = isfSchedule.sensitivities.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.sensitivity) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }
            autotune = appCoordinator.autotune.value
            validate()
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
        }

        private static let formatter = {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"

            return formatter
        }()

        func save() {
            Task {
                let settings = await settingsManager.settings

                let sensitivities = items.map { item -> InsulinSensitivityEntry in
                    let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                    let minutes = Int(date.timeIntervalSince1970 / 60)
                    let rate = self.rateValues[item.rateIndex]
                    return InsulinSensitivityEntry(sensitivity: rate, offset: minutes, start: Self.formatter.string(from: date))
                }
                let profile = InsulinSensitivities(
                    units: units,
                    userPreferredUnits: settings.units,
                    sensitivities: sensitivities
                )
                await isfScheduleStorage.updateIsfSchedule(profile)
            }
        }

        func validate() {
            let uniq = Array(Set(items))
            let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
            sorted.first?.timeIndex = 0
            items = sorted
            if items.isEmpty {
                units = appCoordinator.settings.value.units
            }
        }
    }
}
