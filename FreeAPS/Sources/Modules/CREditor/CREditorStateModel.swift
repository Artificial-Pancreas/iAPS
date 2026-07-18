import SwiftUI

extension CREditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var crScheduleStorage: CarbRatioScheduleStorage!

        @Published var items: [Item] = []
        @Published var autotune: Profile?
        @Published var onlyAutotuneBasals: Bool = false

        let timeValues = stride(from: 0.0, to: TimeInterval.hours(24), by: TimeInterval.minutes(30)).map { $0 }

        let rateValues = stride(from: 1.0, to: 501.0, by: 1.0).map { Decimal($0) / 10 }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        override func subscribe() async {
            let settings = await settingsManager.settings
            onlyAutotuneBasals = settings.onlyAutotuneBasals
            let profile = appCoordinator.crSchedule.value
            items = profile.schedule.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.ratio) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }

            autotune = appCoordinator.autotune.value
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

        func save() {
            Task {
                let schedule = items.map { item -> CarbRatioEntry in
                    let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                    let minutes = Int(date.timeIntervalSince1970 / 60)
                    let rate = self.rateValues[item.rateIndex]
                    return CarbRatioEntry(start: Self.dateFormatter.string(from: date), offset: minutes, ratio: rate)
                }
                let profile = CarbRatios(units: .grams, schedule: schedule)
                await saveProfile(profile)
            }
        }

        func validate() {
            let uniq = Array(Set(items))
            let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
            sorted.first?.timeIndex = 0
            DispatchQueue.main.async {
                self.items = sorted
            }
        }

        private func saveProfile(_ profile: CarbRatios) async {
            await crScheduleStorage.updateCrSchedule(profile)
        }

        private static let dateFormatter = {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()
    }
}
