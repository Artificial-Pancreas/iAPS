
enum Login {
    enum Config {
        static let credentialsKey = "FreeAPS.Credentials"
    }
}

protocol LoginProvider: Provider {
    func authorize(credentials: Credentials)
    var credentials: Credentials? { get }
}
