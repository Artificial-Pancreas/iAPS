import SwiftUI

extension BasalProfileEditor {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: BasalProfileEditorProvider {
        @Injected() var devicemanager: DeviceDataManager!
        @Published var syncInProgress = false
        @Published var items: [Item] = []
        private var maxBasal = 2

        var timeValues: [TimeInterval] {
            stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }
        }

        private(set) var rateValues: [Double] = stride(from: 0.05, to: 10.01, by: 0.05).map { $0 }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        override func subscribe() {
            if let pump = devicemanager.pumpManager {
                rateValues = pump.supportedBasalRates
            }
        }

        func add() {
            var selected = 0
            var rate = 1
            if let last = items.last {
                selected = last.timeIndex + 1
                rate = last.rateIndex
            }

            let newItem = Item(rateIndex: rate, selectedIndex: selected)

            items.append(newItem)
        }

        func save() {}

        func itemsDidChange() {
            DispatchQueue.main.async {
                let uniq = Array(Set(self.items))
                let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                sorted.first?.timeIndex = 0
                self.items = sorted
            }
        }
    }
}
