enum SensorAgeDays: String, Codable, CaseIterable {
    case Zehn_Tage
    case Vierzehn_Tage
    case Fuenfzehn_Tage

    /// Lokalisierter Anzeigename
    var localizedName: String {
        "\(asInt()) Tage"
    }

    /// Anzahl der Tage als Integer
    func asInt() -> Int {
        switch self {
        case .Zehn_Tage: return 10
        case .Vierzehn_Tage: return 14
        case .Fuenfzehn_Tage: return 15
        }
    }

    /// Anzahl der Stunden als Double (optional für Berechnungen)
    var hours: Double {
        Double(asInt()) * 24
    }
}
