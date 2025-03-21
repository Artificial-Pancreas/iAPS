import AppIntents
import Foundation
import Intents

struct OverrideEntity: AppEntity, Identifiable {
    static var defaultQuery = OverrideQuery()

    var id: UUID
    var name: String
    var description: String // Currently not displayed in Shortcuts

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Presets"
}

enum OverrideIntentError: Error {
    case StateIntentUnknownError
    case NoPresets
}

struct ApplyOverrideIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Activate an Override Preset"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription("Allow to activate an overrride preset.")

    internal var intentRequest: OverrideIntentRequest

    init() {
        intentRequest = OverrideIntentRequest()
    }

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
        do {
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
                try await requestConfirmation(
                    result: .result(dialog: "Are you sure you want to activate the Override Preset \(displayName)?")
                )
            }

            let preset = try intentRequest.findPreset(displayName)
            let finalOverrideApply = try intentRequest.enactPreset(preset)
            let isDone = finalOverrideApply != nil ? finalOverrideApply?.isPreset ?? false : false

            let displayDetail: String = isDone ?
                NSLocalizedString("The Profile Override", comment: "") + " \(displayName) " +
                NSLocalizedString("is now activated", comment: "") : "Override Activation Failed"
            return .result(
                dialog: IntentDialog(stringLiteral: displayDetail)
            )
        } catch {
            throw error
        }
    }
}

struct CancelOverrideIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel active override"
    static var description = IntentDescription("Cancel active override.")

    internal var intentRequest: OverrideIntentRequest

    init() {
        intentRequest = OverrideIntentRequest()
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            try intentRequest.cancelOverride()
            return .result(
                dialog: IntentDialog(stringLiteral: "Override canceled")
            )
        } catch {
            throw error
        }
    }
}

struct OverrideQuery: EntityQuery {
    internal var intentRequest: OverrideIntentRequest

    init() {
        intentRequest = OverrideIntentRequest()
    }

    func entities(for identifiers: [OverrideEntity.ID]) async throws -> [OverrideEntity] {
        let presets = intentRequest.fetchIDs(identifiers)
        return presets
    }

    func suggestedEntities() async throws -> [OverrideEntity] {
        let presets = try intentRequest.fetchPresets()
        return presets
    }
}

final class OverrideIntentRequest: BaseIntentsRequest {
    func fetchPresets() throws -> ([OverrideEntity]) {
        let presets = overrideStorage.fetchProfiles().flatMap { preset -> [OverrideEntity] in
            let percentage = preset.percentage != 100 ? preset.percentage.formatted() : ""
            let targetRaw = settingsManager.settings
                .units == .mgdL ? Decimal(Double(truncating: preset.target ?? 0)) : Double(truncating: preset.target ?? 0)
                .asMmolL
            let target = (preset.target != 0 || preset.target != 6) ?
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

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    func findPreset(_ name: String) throws -> OverridePresets {
        let presetFound = overrideStorage.fetchProfiles().filter({ $0.name == name })
        guard let preset = presetFound.first else { throw OverrideIntentError.NoPresets }
        return preset
    }

    func fetchIDs(_ id: [OverrideEntity.ID]) -> [OverrideEntity] {
        let presets = overrideStorage.fetchProfiles().filter { id.contains(UUID(uuidString: $0.id ?? "") ?? UUID()) }
            .map { preset -> OverrideEntity in
                let percentage = preset.percentage != 100 ? preset.percentage.formatted() : ""
                let targetRaw = settingsManager.settings
                    .units == .mgdL ? Decimal(Double(preset.target ?? 0)) : Double(preset.target ?? 0)
                    .asMmolL
                let target = (preset.target != 0 || preset.target != 6) ?
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

    func enactPreset(_ preset: OverridePresets) throws -> Override? {
        guard let overridePreset = overrideStorage.fetchProfilePreset(preset.name ?? "") else {
            return nil
        }
        let lastActiveOveride = overrideStorage.fetchLatestOverride().first
        let isActive = lastActiveOveride?.enabled ?? false

        // Cancel the eventual current active override first
        if isActive {
            let presetName = overrideStorage.isPresetName()
            if let duration = overrideStorage.cancelProfile(), let last = lastActiveOveride {
                // let presetName = overrideStorage.isPresetName()
                let nsString = presetName != nil ? presetName : last.percentage.formatted()
                nightscoutManager.editOverride(nsString!, duration, last.date ?? Date())
            }
        }
        overrideStorage.overrideFromPreset(overridePreset)
        let currentActiveOveride = overrideStorage.fetchLatestOverride().first
        nightscoutManager.uploadOverride(preset.name ?? "", Double(preset.duration ?? 0), currentActiveOveride?.date ?? Date.now)
        return currentActiveOveride
    }

    func cancelOverride() throws {
        // Is there even a saved Override?
        if let activeOveride = overrideStorage.fetchLatestOverride().first {
            let presetName = overrideStorage.isPresetName()
            // Is the Override a Preset?
            if let preset = presetName {
                if let duration = overrideStorage.cancelProfile() {
                    // Update in Nightscout
                    nightscoutManager.editOverride(preset, duration, activeOveride.date ?? Date.now)
                }
            } else if activeOveride.isPreset {
                if let duration = overrideStorage.cancelProfile() {
                    nightscoutManager.editOverride("📉", duration, activeOveride.date ?? Date.now)
                }
            } else {
                let nsString = activeOveride.percentage.formatted() != "100" ? activeOveride.percentage
                    .formatted() + " %" : "Custom"
                if let duration = overrideStorage.cancelProfile() {
                    nightscoutManager.editOverride(nsString, duration, activeOveride.date ?? Date.now)
                }
            }
        }
    }
}
