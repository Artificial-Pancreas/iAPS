import Combine

enum AutotuneConfig {
    enum Config {}
}

protocol AutotuneConfigProvider: Provider {
    var autotune: Autotune? { get }
    func runAutotune() -> AnyPublisher<Autotune?, Never>
    func deleteAutotune()
}
