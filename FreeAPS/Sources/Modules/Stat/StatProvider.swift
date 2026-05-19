import Foundation

extension Stat {
    final class Provider: BaseProvider, StatProvider {
        private let coreDataStorage = CoreDataStorage()

        var dynamicVariables: DynamicVariables? {
            storage.retrieve(OpenAPS.Monitor.dynamicVariables, as: DynamicVariables.self)
        }

        func reasons() -> [IOBData]? {
            let reasons = coreDataStorage.fetchReasons(interval: DateFilter().day)
            guard reasons.count > 3 else { return nil }
            return reasons.compactMap { entry -> IOBData in
                IOBData(
                    date: entry.date ?? Date(),
                    iob: (entry.iob ?? 0) as Decimal,
                    cob: (entry.cob ?? 0) as Decimal
                )
            }
        }
    }
}
