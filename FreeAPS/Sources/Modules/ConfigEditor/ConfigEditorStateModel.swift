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
        /// non-nil when the last save was rejected; drives the error alert in the view
        @Published var saveError: String?

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
                do {
                    // the storage validates the raw text, only saves valid values
                    // invalid edits are rejected and an error is displayed
                    try await persist(configText, as: file)
                    saveError = nil
                } catch {
                    saveError = Self.message(for: error, file: file)
                }
            }
        }

        private func load(file: String) async -> RawJSON {
            await storage.retrieveRaw(file) ?? ""
        }

        private func persist(_ value: RawJSON, as file: String) async throws {
            switch file {
            case OpenAPS.FreeAPS.settings:
                try await settingsManager.saveRawSettings(value)
            case OpenAPS.Settings.preferences:
                try await settingsManager.saveRawPreferences(value)
            case OpenAPS.Settings.settings:
                try await settingsManager.saveRawPumpSettings(value)
            case OpenAPS.Monitor.glucose:
                try await glucoseStorage.saveRawJSON(value)
            case OpenAPS.Monitor.pumpHistory:
                try await pumpHistoryStorage.saveRawJSON(value)
            case OpenAPS.Monitor.carbHistory:
                try await carbsStorage.saveRawJSON(value)
            case OpenAPS.Settings.tempTargets:
                try await tempTargetsStorage.saveRawJSON(value)
            case OpenAPS.Settings.basalProfile:
                try await basalProfileStorage.saveRawJSON(value)
            case OpenAPS.Settings.autotune:
                try await autotuneStorage.saveRawJSON(value)
            case OpenAPS.Settings.insulinSensitivities:
                try await isfScheduleStorage.saveRawJSON(value)
            case OpenAPS.Settings.carbRatios:
                try await crScheduleStorage.saveRawJSON(value)
            case OpenAPS.Settings.bgTargets:
                try await bgTargetsScheduleStorage.saveRawJSON(value)
            default:
                try await persistUnbacked(value, as: file)
            }
        }

        /// Files without a dedicated storage
        /// `.js` scripts are saved as-is;
        /// any other file is checked for well-formed JSON
        private func persistUnbacked(_ value: RawJSON, as file: String) async throws {
            if file.hasSuffix(".js") {
                await storage.save(value, as: file)
                return
            }
            guard let data = value.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
            else {
                throw SaveError.invalidJSON
            }
            await storage.save(value, as: file)
        }

        private static func message(for error: Error, file: String) -> String {
            let reason: String
            switch error {
            case let DecodingError.dataCorrupted(context):
                reason = context.debugDescription
            case let DecodingError.keyNotFound(key, context):
                reason = "missing key “\(key.stringValue)” \(codingPathSuffix(context))"
            case let DecodingError.valueNotFound(_, context):
                reason = "missing value \(codingPathSuffix(context))"
            case let DecodingError.typeMismatch(_, context):
                reason = "wrong type \(codingPathSuffix(context))"
            default:
                reason = error.localizedDescription
            }
            return String(
                format: NSLocalizedString("“%@” was not saved.\n\n%@", comment: "Config editor save error"),
                file,
                reason
            )
        }

        private static func codingPathSuffix(_ context: DecodingError.Context) -> String {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "at “\(path)”. \(context.debugDescription)"
        }
    }

    enum SaveError: LocalizedError {
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .invalidJSON:
                return NSLocalizedString("The text isn’t valid JSON.", comment: "Config editor save error")
            }
        }
    }
}
