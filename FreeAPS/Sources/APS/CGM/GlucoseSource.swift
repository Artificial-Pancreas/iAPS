import Combine

protocol SourceInfoProvider {
    func sourceInfo() -> [String: Any]?
}

protocol GlucoseSource: SourceInfoProvider {
    func fetch() -> AnyPublisher<[BloodGlucose], Never>
}

extension GlucoseSource {
    func sourceInfo() -> [String: Any]? { nil }
}
