import CoreData
import Foundation

// a snapshot (DTO) of a CoreData TempTargetsSlider entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct TempTargetsSliderSnapshot: Sendable {
    let id: String?
    let date: Date?
    let defaultHBT: Double
    let duration: Decimal?
    let enabled: Bool
    let hbt: Double
    let isPreset: Bool
}

extension TempTargetsSliderSnapshot {
    static func create(from slider: TempTargetsSlider) -> TempTargetsSliderSnapshot {
        TempTargetsSliderSnapshot(
            id: slider.id,
            date: slider.date,
            defaultHBT: slider.defaultHBT,
            duration: slider.duration?.decimalValue,
            enabled: slider.enabled,
            hbt: slider.hbt,
            isPreset: slider.isPreset
        )
    }
}
