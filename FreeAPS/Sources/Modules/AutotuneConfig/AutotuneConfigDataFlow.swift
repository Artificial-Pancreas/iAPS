import Combine

enum AutotuneConfig {
    enum Config {}
}

protocol AutotuneConfigProvider: Provider {
    var autotune: Autotune? { get }
    func runAutotune() -> AnyPublisher<Autotune?, Never>
    func deleteAutotune()

    /// The persisted Reasons-based ISF schedule, if one exists.
    var reasonsISFSchedule: ReasonsISFSchedule? { get }
    /// The current insulin-sensitivity profile.
    var currentISFProfile: InsulinSensitivities { get }
    /// Overwrite the insulin-sensitivity profile with new values.
    func saveISFProfile(_ profile: InsulinSensitivities)
}
