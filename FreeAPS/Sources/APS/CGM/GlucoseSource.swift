import Combine

protocol SourceInfoProvider {
    func sourceInfo() -> [String: Any]?
}

protocol GlucoseSource: SourceInfoProvider {
    func fetch(_ heartbeat: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never>
}

extension GlucoseSource {
    func sourceInfo() -> [String: Any]? { nil }
}
