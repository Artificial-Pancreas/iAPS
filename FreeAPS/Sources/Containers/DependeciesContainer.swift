import Swinject

protocol DependeciesContainer {
    static func register(container: Container)
    static func setup()
}

extension DependeciesContainer {
    static func setup() {}
}
