import AuthenticationServices

enum Login {
    enum Config {
        static let credentialsKey = "FreeAPS.Credentials"
    }
}

protocol LoginProvider: Provider {
    func authorize(credentials: ASAuthorizationAppleIDCredential)
    var credentials: ASAuthorizationAppleIDCredential? { get }
}

struct CredentialsWrapper: Codable {
    enum CodingKeys: String, CodingKey {
        case credentials
    }

    var credentials: ASAuthorizationAppleIDCredential

    init(_ credentials: ASAuthorizationAppleIDCredential) {
        self.credentials = credentials
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let data = try NSKeyedArchiver.archivedData(withRootObject: credentials, requiringSecureCoding: true)
        try container.encode(data, forKey: .credentials)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode(Data.self, forKey: .credentials)
        credentials = try (NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? ASAuthorizationAppleIDCredential)!
    }
}
