
struct ContactTrickEntry: JSON, Equatable {
    var enabled: Bool = false
    var layout: ContactTrickLayout = .single
    var ring1: ContactTrickLargeRing = .none
    var primary: ContactTrickValue = .glucose
    var top: ContactTrickValue = .none
    var bottom: ContactTrickValue = .none
    var contactId: String? = nil
    var displayName: String? = nil
    var darkMode: Bool = true
    var ringWidth: Int = 7
    var ringGap: Int = 2
    var fontSize: Int = 100
    var fontName: String = "Default Font"
    var fontWeight: FontWeight = .medium
    var fontTracking: FontTracking = .normal

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
        case primary
        case top
        case bottom
        case contactId
        case displayName
        case darkMode
        case ringWidth
        case ringGap
        case fontSize
        case fontName
        case fontWeight
        case fontTracking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let layout = try container.decodeIfPresent(ContactTrickLayout.self, forKey: .layout) ?? .single
        let ring1 = try container.decodeIfPresent(ContactTrickLargeRing.self, forKey: .ring1) ?? .none
        let primary = try container.decodeIfPresent(ContactTrickValue.self, forKey: .primary) ?? .glucose
        let top = try container.decodeIfPresent(ContactTrickValue.self, forKey: .top) ?? .none
        let bottom = try container.decodeIfPresent(ContactTrickValue.self, forKey: .bottom) ?? .none
        let contactId = try container.decodeIfPresent(String.self, forKey: .contactId)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let darkMode = try container.decodeIfPresent(Bool.self, forKey: .darkMode) ?? true
        let ringWidth = try container.decodeIfPresent(Int.self, forKey: .ringWidth) ?? 7
        let ringGap = try container.decodeIfPresent(Int.self, forKey: .ringGap) ?? 2
        let fontSize = try container.decodeIfPresent(Int.self, forKey: .fontSize) ?? 100
        let fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "Default Font"
        let fontWeight = try container.decodeIfPresent(FontWeight.self, forKey: .fontWeight) ?? .regular
        let fontTracking = try container.decodeIfPresent(FontTracking.self, forKey: .fontTracking) ?? .normal

        self = ContactTrickEntry(
            enabled: enabled,
            layout: layout,
            ring1: ring1,
            primary: primary,
            top: top,
            bottom: bottom,
            contactId: contactId,
            displayName: displayName,
            darkMode: darkMode,
            ringWidth: ringWidth,
            ringGap: ringGap,
            fontSize: fontSize,
            fontName: fontName,
            fontWeight: fontWeight,
            fontTracking: fontTracking
        )
    }
}
