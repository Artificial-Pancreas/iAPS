import AppIntents
import Foundation
import Intents
import Swinject

struct tempPreset: AppEntity, Identifiable {
    static let defaultQuery = tempPresetsQuery()

    let id: UUID
    let name: String
    let targetTop: Decimal?
    let targetBottom: Decimal?
    let duration: Decimal

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Presets"

    /// Nil when the stored preset's id is not a UUID (Shortcuts can only address presets by UUID).
    static func convert(_ tempTarget: TempTarget) -> tempPreset? {
        guard let id = UUID(uuidString: tempTarget.id) else { return nil }
        return tempPreset(
            id: id,
            name: tempTarget.displayName,
            targetTop: tempTarget.targetTop,
            targetBottom: tempTarget.targetBottom,
            duration: tempTarget.duration
        )
    }
}
