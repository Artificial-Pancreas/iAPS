import Combine

enum AutotuneConfig {
    enum Config {}
}

protocol AutotuneConfigProvider: Provider {
    var autotune: Autotune? { get }
    func runAutotune() -> AnyPublisher<Autotune?, Never>
    func deleteAutotune()
    var reasonsISFSchedule: ReasonsISFSchedule? { get }
    var currentISFProfile: InsulinSensitivities? { get }
    func saveISFProfile(_ profile: InsulinSensitivities)
}
