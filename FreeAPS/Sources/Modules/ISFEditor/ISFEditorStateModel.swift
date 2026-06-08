import SwiftUI
import Swinject

extension ISFEditor {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner {
        @Injected() private var storage: FileStorage!
        @Injected() private var appCoordinator: AppCoordinator!
        private let coreDataStorage = CoreDataStorage()

        @Published var items: [Item] = []
        private(set) var autosensISF: Decimal?
        private(set) var autosensRatio: Decimal = 0

        @Published var suggestion: Suggestion?
        @Published var autotune: Autotune?
        @Published var sensitivity: NSDecimalNumber?

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        override init(resolver: Resolver) {
            super.init(resolver: resolver)
        }

        var rateValues: [Decimal] {
            switch units {
            case .mgdL:
                return stride(from: 9, to: 540.01, by: 1.0).map { Decimal($0) }
            case .mmolL:
                return stride(from: 1.0, to: 301.0, by: 1.0).map { ($0.decimal ?? .zero) / 10 }
            }
        }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() async {
            suggestion = await storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)

            fetchSensitivity()

            let isfSchedule = await provider.isfSchedule
            units = isfSchedule.units
            items = isfSchedule.sensitivities.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.sensitivity) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }
            autotune = await provider.autotune

            let autosens = await provider.autosense
            if let newISF = autosens.newisf {
                switch units {
                case .mgdL:
                    autosensISF = newISF
                case .mmolL:
                    autosensISF = newISF * GlucoseUnits.exchangeRate
                }
            }

            autosensRatio = autosens.ratio

            observe(appCoordinator.suggestions) { me, suggestion in
                await me.suggestionUpdated(suggestion)
            }
        }

        private func suggestionUpdated(_ suggestion: Suggestion?) {
            self.suggestion = suggestion
            fetchSensitivity()
        }

        private func fetchSensitivity() {
            if let suggestion = coreDataStorage.fetchReason() {
                sensitivity = suggestion.isf ?? 15
            } else {
                sensitivity = nil
            }
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

        private let formatter = {
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
                    return InsulinSensitivityEntry(sensitivity: rate, offset: minutes, start: formatter.string(from: date))
                }
                let profile = InsulinSensitivities(
                    units: units,
                    userPrefferedUnits: settings.units,
                    sensitivities: sensitivities
                )
                await provider.saveProfile(profile)
            }
        }

        func validate() {
            let uniq = Array(Set(items))
            let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
            sorted.first?.timeIndex = 0
            DispatchQueue.main.async {
                self.items = sorted
            }

            // TODO: what is this for?
//            if self.items.isEmpty {
//                self.units = self.settingsManager.settings.units
//            }
        }
    }
}
