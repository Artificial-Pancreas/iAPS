
struct ContactTrickEntry: JSON, Equatable {
    var enabled: Bool = false
    var layout: ContactTrickLayout = .single
    var ring1: ContactTrickLargeRing = .none
    var ring2: ContactTrickLargeRing = .none
    var primary: ContactTrickValue = .glucose
    var top: ContactTrickValue = .none
    var bottom: ContactTrickValue = .none
    var contactId: String? = nil
    var displayName: String? = nil
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
        case ring1
        case ring2
        case primary
        case top
        case bottom
        case contactId
        case displayName
        case darkMode
        case fontSize
        case fontName
        case fontWeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let enabled = try container.decode(Bool.self, forKey: .enabled)
        let layout = try container.decode(ContactTrickLayout.self, forKey: .layout)
        let ring1 = try container.decode(ContactTrickLargeRing.self, forKey: .ring1)
        let ring2 = try container.decode(ContactTrickLargeRing.self, forKey: .ring2)
        let primary = try container.decode(ContactTrickValue.self, forKey: .primary)
        let top = try container.decode(ContactTrickValue.self, forKey: .top)
        let bottom = try container.decode(ContactTrickValue.self, forKey: .bottom)
        let contactId = try container.decodeIfPresent(String.self, forKey: .contactId)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let darkMode = try container.decode(Bool.self, forKey: .darkMode)
        let fontSize = try container.decode(Int.self, forKey: .fontSize)
        let fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "Default Font"
        let fontWeight = try container.decode(FontWeight.self, forKey: .fontWeight)

        self = ContactTrickEntry(
            enabled: enabled,
            layout: layout,
            ring1: ring1,
            ring2: ring2,
            primary: primary,
            top: top,
            bottom: bottom,
            contactId: contactId,
            displayName: displayName,
            darkMode: darkMode,
            fontSize: fontSize,
            fontName: fontName,
            fontWeight: fontWeight
        )
    }
}
