import HealthKit
import LoopKit
import SwiftUI

extension PumpSettingsEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var deviceManager: DeviceDataManager!

        @Published var isDanaPump = false
        @Published var maxBasal: Decimal = 0.0
        @Published var maxBolus: Decimal = 0.0
        @Published var dia: Decimal = 0.0
        @Published var syncInProgress = false

        override func subscribe() async {
            let settings = await settingsManager.pumpSettings
            maxBasal = settings.maxBasal
            maxBolus = settings.maxBolus
            dia = settings.insulinActionCurve
            isDanaPump = detectDanaPump()
        }

        func save() {
            Task {
                syncInProgress = true
                do {
                    let savedSettings = try await savePumpSettings(
                        settings: PumpSettings(
                            insulinActionCurve: dia,
                            maxBolus: maxBolus,
                            maxBasal: maxBasal
                        )
                    )

                    self.maxBasal = savedSettings.maxBasal
                    self.maxBolus = savedSettings.maxBolus
                } catch {
                    debug(.default, "failed to save pump settings: \(error.localizedDescription)")
                }
                self.syncInProgress = false
            }
        }

        private func detectDanaPump() -> Bool {
            guard let pump = appCoordinator.pumpInfo.value else {
                // TODO: why true?
                return true
            }

            // TODO: use plugin identifier instead (adda function to the KnownPlugins)
            return pump.name.contains("Dana")
        }

        private func savePumpSettings(settings: PumpSettings) async throws -> PumpSettings {
            guard let actual = try await deviceManager.syncDeliveryLimits(pumpSettings: settings) else {
                // no pump configured, just save to storage
                await settingsManager.updatePumpSettings(settings)
                return settings
            }
            let pumpAdjustedSettings = PumpSettings(
                insulinActionCurve: settings.insulinActionCurve,
                maxBolus: Decimal(
                    actual.maximumBolus ?? Double(settings.maxBolus)
                ),
                maxBasal: Decimal(
                    actual.maximumBasalRate ?? Double(settings.maxBasal)
                )
            )
            await settingsManager.updatePumpSettings(pumpAdjustedSettings)
            return pumpAdjustedSettings
        }
    }
}
