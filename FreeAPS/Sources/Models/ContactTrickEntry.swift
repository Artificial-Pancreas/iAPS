
struct ContactTrickEntry: JSON, Equatable {
    var enabled: Bool = false
    var layout: ContactTrickLayout
    var primary: ContactTrickValue = .bg
    var secondary: ContactTrickValue? = .trend
    var contactId: String? = nil
    var displayName: String? = nil
    var trend: Bool = false
    var ring: Bool = false
    var darkMode: Bool = true
    var fontSize: Int = 100
    var fontName: String = "Default Font"
    var fontWeight: FontWeight = .medium

    func isDefaultFont() -> Bool {
        fontName == "Default Font"
    }
}

protocol ContactTrickObserver {
    func basalProfileDidChange(_ entry: [ContactTrickEntry])
}

extension ContactTrickEntry {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case layout
        case primary
        case secondary
        case contactId
        case displayName
        case trend
        case ring
        case darkMode
        case fontSize
        case fontName
        case fontWeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let enabled = try container.decode(Bool.self, forKey: .enabled)
        let layout = try container.decode(ContactTrickLayout.self, forKey: .layout)
        let primary = try container.decode(ContactTrickValue.self, forKey: .primary)
        let secondary = try container.decodeIfPresent(ContactTrickValue.self, forKey: .secondary)
        let contactId = try container.decodeIfPresent(String.self, forKey: .contactId)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let trend = try container.decode(Bool.self, forKey: .trend)
        let ring = try container.decode(Bool.self, forKey: .ring)
        let darkMode = try container.decode(Bool.self, forKey: .darkMode)
        let fontSize = try container.decode(Int.self, forKey: .fontSize)
        let fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "Default Font"
        let fontWeight = try container.decode(FontWeight.self, forKey: .fontWeight)

        self = ContactTrickEntry(
            enabled: enabled,
            layout: layout,
            primary: primary,
            secondary: secondary,
            contactId: contactId,
            displayName: displayName,
            trend: trend,
            ring: ring,
            darkMode: darkMode,
            fontSize: fontSize,
            fontName: fontName,
            fontWeight: fontWeight
        )
    }
}
