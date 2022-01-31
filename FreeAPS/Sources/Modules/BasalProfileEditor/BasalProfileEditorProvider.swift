import Combine
import Foundation
import LoopKit

extension BasalProfileEditor {
    final class Provider: BaseProvider, BasalProfileEditorProvider {
        private let processQueue = DispatchQueue(label: "BasalProfileEditorProvider.processQueue")

        var profile: [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
                ?? []
        }

        var autotune: Autotune? {
            storage.retrieve(OpenAPS.Settings.autotune, as: Autotune.self)
        }

        var supportedBasalRates: [Decimal]? {
            deviceManager.pumpManager?.supportedBasalRates.map { Decimal($0) }
        }

        func saveProfile(_ profile: [BasalProfileEntry]) -> AnyPublisher<Void, Error> {
            guard let pump = deviceManager?.pumpManager else {
                storage.save(profile, as: OpenAPS.Settings.basalProfile)
                return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
            }

            let syncValues = profile.map {
                RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
            }

            return Future { promise in
                pump.syncBasalRateSchedule(items: syncValues) { result in
                    switch result {
                    case .success:
                        self.storage.save(profile, as: OpenAPS.Settings.basalProfile)
                        promise(.success(()))
                    case let .failure(error):
                        promise(.failure(error))
                    }
                }
            }.eraseToAnyPublisher()
        }

        func readProfile() -> AnyPublisher<Void, Error> {
            guard let pump = deviceManager?.pumpManager else {
                // storage.save(profile, as: OpenAPS.Settings.basalProfile)
                return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
            }

            // let syncValues = profile.map {
            //    RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
            // }

            return Future { promise in
                pump.getBasalRateSchedule { result in
                    switch result {
                    case let .success(scheduleItems):
                        var newProfile: [BasalProfileEntry] = []
                        for item in scheduleItems.items {
                            NSLog("getBasalRateSchedule \(item.startTime) \(item.value)")
                            let startMinutes = Int(item.startTime / 60) // seconds to minutes
                            let start = String(format: "%2d:%2d", startMinutes / 60, startMinutes % 60)
                            let rate = Decimal(item.value)
                            newProfile.append(BasalProfileEntry(
                                start: start,
                                minutes: startMinutes,
                                rate: rate
                            ))
                        }

                        for p in newProfile {
                            NSLog("getBasalRateSchedule \(p.start) \(p.minutes) \(p.rate)")
                        }

                        self.storage.save(newProfile, as: OpenAPS.Settings.basalProfile)
                        // self.profile = newProfile
                        promise(.success(()))
                    case let .failure(error):
                        promise(.failure(error))
                    }
                }
            }.eraseToAnyPublisher()
        }
    }
}
