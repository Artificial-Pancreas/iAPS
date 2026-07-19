import SwiftUI
import Swinject

extension ConfigEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var storage: FileStorage!
        @Injected() private var glucoseStorage: GlucoseStorage!
        @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() private var carbsStorage: CarbsStorage!
        @Injected() private var tempTargetsStorage: TempTargetsStorage!
        @Injected() private var basalProfileStorage: BasalProfileStorage!
        @Injected() private var autotuneStorage: AutotuneStorage!
        @Injected() private var isfScheduleStorage: IsfScheduleStorage!
        @Injected() private var crScheduleStorage: CarbRatioScheduleStorage!
        @Injected() private var bgTargetsScheduleStorage: BgTargetsScheduleStorage!

        let file: String
        @Published var configText = ""
        @Published var urlForFile: URL?

        init(resolver: Resolver, file: String) {
            self.file = file
            super.init(resolver: resolver)
        }

        override func subscribe() async {
            configText = await load(file: file)
            urlForFile = await storage.urlFor(file: file)
        }

        func save() {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            Task {
                // TODO: display an error in the UI in case of invalid JSON?
                await persist(configText, as: file)
                // the edited file may back an in-memory cache - reset it so the change takes effect without a restart
                switch file {
                case OpenAPS.FreeAPS.settings,
                     OpenAPS.Settings.preferences,
                     OpenAPS.Settings.settings:
                    await settingsManager.resetCachedSettings()
                case OpenAPS.Monitor.glucose:
                    await glucoseStorage.resetCache()
                case OpenAPS.Monitor.pumpHistory:
                    await pumpHistoryStorage.resetCache()
                case OpenAPS.Monitor.carbHistory:
                    await carbsStorage.resetCache()
                case OpenAPS.Settings.tempTargets:
                    await tempTargetsStorage.resetCache()
                case OpenAPS.Settings.basalProfile:
                    await basalProfileStorage.resetCache()
                case OpenAPS.Settings.autotune:
                    await autotuneStorage.resetCache()
                case OpenAPS.Settings.insulinSensitivities:
                    await isfScheduleStorage.resetCache()
                case OpenAPS.Settings.carbRatios:
                    await crScheduleStorage.resetCache()
                case OpenAPS.Settings.bgTargets:
                    await bgTargetsScheduleStorage.resetCache()
                default:
                    break
                }
            }
        }

        private func load(file: String) async -> RawJSON {
            await storage.retrieveRaw(file) ?? ""
        }

        private func persist(_ value: RawJSON, as file: String) async {
            if file.hasSuffix(".js") {
                await storage.save(value, as: file)
                return
            }

            guard let data = value.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else {
                warning(.service, "Invalid JSON")
                return
            }
            await storage.save(value, as: file)
        }
    }
}
