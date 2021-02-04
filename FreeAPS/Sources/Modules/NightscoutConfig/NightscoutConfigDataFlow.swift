enum NightscoutConfig {
    enum Config {
        static let urlKey = "NightscoutConfig.url"
        static let secretKey = "NightscoutConfig.secret"
    }
}

protocol NightscoutConfigProvider: Provider {}
