struct WatchMessage: Sendable {
    let carbs: Double?
    let fat: Double?
    let protein: Double?
    let tempTarget: String?
    let override: String?
    let bolus: Double?

    init(_ dict: [String: Any]) {
        carbs = dict["carbs"] as? Double
        fat = dict["fat"] as? Double
        protein = dict["protein"] as? Double
        tempTarget = dict["tempTarget"] as? String
        override = dict["override"] as? String
        bolus = dict["bolus"] as? Double
    }
}

struct WatchReply: Sendable {
    let confirmation: Bool

    var dict: [String: Any] { ["confirmation": confirmation] }

    static let confirmed = WatchReply(confirmation: true)
    static let denied = WatchReply(confirmation: false)
}
