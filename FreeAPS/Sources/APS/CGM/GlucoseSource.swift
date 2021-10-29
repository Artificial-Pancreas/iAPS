import Combine

protocol GlucoseSource {
    func fetch() -> AnyPublisher<[BloodGlucose], Never>
}
