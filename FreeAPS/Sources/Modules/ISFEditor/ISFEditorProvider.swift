import Foundation
import Swinject

extension ISFEditor {
    final class Provider: ISFEditorProvider, Sendable {
        private let storage: FileStorage

        init(resolver: Resolver) {
            storage = resolver.resolve(FileStorage.self)!
        }

        var isfSchedule: InsulinSensitivities {
            get async {
                await storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                    ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                    ?? InsulinSensitivities(
                        units: .mmolL,
                        userPrefferedUnits: .mmolL,
                        sensitivities: []
                    )
            }
        }

        func saveProfile(_ profile: InsulinSensitivities) async {
            await storage.save(profile, as: OpenAPS.Settings.insulinSensitivities)
        }

        var autosense: Autosens {
            get async {
                await storage.retrieve(OpenAPS.Settings.autosense, as: Autosens.self)
                    ?? Autosens(from: OpenAPS.defaults(for: OpenAPS.Settings.autosense))
                    ?? Autosens(ratio: 1, newisf: nil, timestamp: nil)
            }
        }

        var autotune: Autotune? {
            get async {
                await storage.retrieve(OpenAPS.Settings.autotune, as: Autotune.self)
            }
        }
    }
}
