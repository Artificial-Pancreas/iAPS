import AppIntents
import Foundation
import Intents

struct OverrideEntity: AppEntity, Identifiable {
    static let defaultQuery = OverrideQuery()

    var id: UUID
    var name: String
    var description: String // Currently not displayed in Shortcuts

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Presets"
}

enum OverrideIntentError: Error {
    case StateIntentUnknownError
    case NoPresets
}

struct ApplyOverrideIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static let title: LocalizedStringResource = "Activate an Override Preset"

    // Description of the action in the Shortcuts app
    static let description = IntentDescription("Allow to activate an overrride preset.")

    @Parameter(title: "Preset") var preset: OverrideEntity?

    @Parameter(
        title: "Confirm Before activating",
        description: "If toggled, you will need to confirm before activating",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\ApplyOverrideIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        let intentRequest = OverrideIntentRequest()
        let presetToApply: OverrideEntity
        if let preset = preset {
            presetToApply = preset
        } else {
            presetToApply = try await $preset.requestDisambiguation(
                among: intentRequest.fetchPresets(),
                dialog: "Which override preset would you like to activate?"
            )
        }

        let displayName: String = presetToApply.name
        if confirmBeforeApplying {
            // deprecated, but the fix is iOS 18+ only
            try await requestConfirmation(
                result: .result(dialog: "Are you sure you want to activate the Override Preset \(displayName)?")
            )
        }

        let preset = try await intentRequest.findPreset(displayName)
        let finalOverrideApply = try await intentRequest.enactPreset(preset)
        let isDone = finalOverrideApply?.isPreset ?? false

        let displayDetail: String = isDone ?
            NSLocalizedString("The Profile Override", comment: "") + " \(displayName) " +
            NSLocalizedString("is now activated", comment: "") : "Override Activation Failed"
        return .result(
            dialog: IntentDialog(stringLiteral: displayDetail)
        )
    }
}

struct CancelOverrideIntent: AppIntent {
    static let title: LocalizedStringResource = "Cancel active override"
    static let description = IntentDescription("Cancel active override.")

    @MainActor func perform() async throws -> some ProvidesDialog {
        let intentRequest = OverrideIntentRequest()
        await intentRequest.cancelOverride()
        return .result(
            dialog: IntentDialog(stringLiteral: "Override canceled")
        )
    }
}

struct OverrideQuery: EntityQuery {
    func entities(for identifiers: [OverrideEntity.ID]) async throws -> [OverrideEntity] {
        let intentRequest = OverrideIntentRequest()
        let presets = await intentRequest.fetchIDs(identifiers)
        return presets
    }

    func suggestedEntities() async throws -> [OverrideEntity] {
        let intentRequest = OverrideIntentRequest()
        return try await intentRequest.fetchPresets()
    }
}

final class OverrideIntentRequest: BaseIntentsRequest {
    func fetchPresets() async throws -> ([OverrideEntity]) {
        let settings = await settingsManager.settings
        let fetched = await overrideStorage.fetchProfiles()
        let glucoseFormatter = self.glucoseFormatter(settings)
        let presets = fetched.flatMap { preset -> [OverrideEntity] in
            let percentage = preset.percentage != 100 ? preset.percentage.formatted() : ""

            let targetRaw = settings
                .units == .mgdL ? (preset.target ?? 0) : (preset.target ?? 0)
                .asMmolL
            let target = (preset.target != 0 && preset.target != 6) ?
                (glucoseFormatter.string(from: targetRaw as NSNumber) ?? "") : ""
            let string = percentage != "" ? percentage + ", " + target : target

            return [OverrideEntity(
                id: UUID(uuidString: preset.id ?? "") ?? UUID(),
                name: preset.name ?? "",
                description: string
            )]
        }
        return presets
    }

    private func glucoseFormatter(_ settings: FreeAPSSettings) -> NumberFormatter {
        switch settings.units {
        case .mmolL: return Self.glucoseFormatterMmol
        case .mgdL: return Self.glucoseFormatterMgdl
        }
    }

    private static let glucoseFormatterMmol = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let glucoseFormatterMgdl = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    func findPreset(_ name: String) async throws -> OverridePresetsSnapshot {
        let presetFound = await overrideStorage.fetchProfiles().filter({ $0.name == name })
        guard let preset = presetFound.first else { throw OverrideIntentError.NoPresets }
        return preset
    }

    func fetchIDs(_ id: [OverrideEntity.ID]) async -> [OverrideEntity] {
        let settings = await settingsManager.settings
        let glucoseFormatter = self.glucoseFormatter(settings)
        let presets = await overrideStorage.fetchProfiles().filter { id.contains(UUID(uuidString: $0.id ?? "") ?? UUID()) }
            .map { preset -> OverrideEntity in
                let percentage = preset.percentage != 100 ? preset.percentage.formatted() : ""
                let targetRaw = settings
                    .units == .mgdL ? (preset.target ?? 0) : (preset.target ?? 0)
                    .asMmolL
                let target = (preset.target != 0 && preset.target != 6) ?
                    (glucoseFormatter.string(from: targetRaw as NSNumber) ?? "") : ""
                let string = percentage != "" ? percentage + ", " + target : target

                return OverrideEntity(
                    id: UUID(uuidString: preset.id ?? "") ?? UUID(),
                    name: preset.name ?? "",
                    description: string
                )
            }
        return presets
    }

    func enactPreset(_ preset: OverridePresetsSnapshot) async throws -> OverrideSnapshot? {
        guard let overridePreset = await overrideStorage.fetchProfilePreset(preset.name ?? "") else {
            return nil
        }
        let lastActiveOveride = await overrideStorage.fetchLatestOverride().first
        let isActive = lastActiveOveride?.enabled ?? false

        // Cancel the eventual current active override first
        if isActive {
            let presetName = await overrideStorage.isPresetName()
            if let duration = await overrideStorage.cancelProfile(), let last = lastActiveOveride {
                let nsString = presetName ?? last.percentage.formatted()
                await nightscoutManager.uploadOverride(nsString, duration, last.date ?? Date())
            }
        }
        await overrideStorage.overrideFromPreset(overridePreset)
        let currentActiveOveride = await overrideStorage.fetchLatestOverride().first
        await nightscoutManager.uploadOverride(
            preset.name ?? "",
            Double(preset.duration ?? 0),
            currentActiveOveride?.date ?? Date.now
        )
        return currentActiveOveride
    }

    func cancelOverride() async {
        // Is there even a saved Override?
        if let activeOveride = await overrideStorage.fetchLatestOverride().first {
            let presetName = await overrideStorage.isPresetName()
            // Is the Override a Preset?
            if let preset = presetName {
                if let duration = await overrideStorage.cancelProfile() {
                    // Update in Nightscout
                    await nightscoutManager.uploadOverride(preset, duration, activeOveride.date ?? Date.now)
                }
            } else if activeOveride.isPreset {
                if let duration = await overrideStorage.cancelProfile() {
                    await nightscoutManager.uploadOverride("📉", duration, activeOveride.date ?? Date.now)
                }
            } else {
                let nsString = activeOveride.percentage.formatted() != "100" ? activeOveride.percentage
                    .formatted() + " %" : "Custom"
                if let duration = await overrideStorage.cancelProfile() {
                    await nightscoutManager.uploadOverride(nsString, duration, activeOveride.date ?? Date.now)
                }
            }
        }
    }
}
