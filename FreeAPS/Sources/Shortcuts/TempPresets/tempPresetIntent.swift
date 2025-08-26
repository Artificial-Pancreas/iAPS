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

    static func convert(_ tempTarget: TempTarget) -> tempPreset {
        tempPreset(
            id: UUID(uuidString: tempTarget.id)!,
            name: tempTarget.displayName,
            targetTop: tempTarget.targetTop,
            targetBottom: tempTarget.targetBottom,
            duration: tempTarget.duration
        )
    }
}
