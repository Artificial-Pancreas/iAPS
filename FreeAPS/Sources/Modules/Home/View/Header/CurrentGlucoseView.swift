import SwiftUI

struct CurrentGlucoseView: View {
    let recentGlucose: BloodGlucose?
    let delta: Int?
    let units: GlucoseUnits
    let lowGlucose: Decimal
    let highGlucose: Decimal
    let alwaysUseColors: Bool
    let displayDelta: Bool
    let scrolling: Bool
    let timerDate: Date

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sizeCategory) private var fontSize
    @Environment(AppUIState.self) private var appUIState

    private static let mgdLFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let mmolLFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let manualMmolLFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .ceiling
        return formatter
    }()

    private static let mgdLDeltaFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+ "
        formatter.negativePrefix = "- "
        return formatter
    }()

    private static let mmolLDeltaFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+ "
        formatter.negativePrefix = "- "
        return formatter
    }()

    private static let timaAgoFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.negativePrefix = ""
        return formatter
    }()

    private static let decimalString: String = NumberFormatter().decimalSeparator

    private var glucoseFormatter: NumberFormatter {
        units == .mmolL ? Self.mmolLFormatter : Self.mgdLFormatter
    }

    private var manualGlucoseFormatter: NumberFormatter {
        units == .mmolL ? Self.manualMmolLFormatter : Self.mgdLFormatter
    }

    private var deltaFormatter: NumberFormatter {
        units == .mmolL ? Self.mmolLDeltaFormatter : Self.mgdLDeltaFormatter
    }

    var body: some View {
        glucoseView
            .dynamicTypeSize(DynamicTypeSize.medium ... DynamicTypeSize.xLarge)
    }

    var glucoseView: some View {
        ZStack {
            if let recent = recentGlucose {
                if displayDelta, !scrolling, let deltaInt = delta,
                   !(units == .mmolL && abs(deltaInt) <= 1) { deltaView(deltaInt) }
                VStack(spacing: 15) {
                    let formatter = recent.type == GlucoseType.manual.rawValue ? manualGlucoseFormatter : glucoseFormatter
                    let value = Decimal(recent.glucose)
                    let string =
                        formatter
                            .string(from: Double(units == .mmolL ? value.asMmolL : value) as NSNumber) ??
                            ""

                    glucoseText(string).asAny()
                        .background { glucoseDrop }
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: recent.glucose)
                    if !scrolling {
                        let minutesAgo = timerDate.timeIntervalSince(recent.dateString) / 60
                        let text = Self.timaAgoFormatter.string(for: Double(minutesAgo)) ?? ""
                        Text(
                            minutesAgo <= 1 ? NSLocalizedString("Now", comment: "") :
                                (text + " " + NSLocalizedString("min", comment: "Short form for minutes") + " ")
                        )
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: minutesAgo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .offset(x: 1, y: fontSize >= .extraLarge ? -3 : 0)
                    }
                }
            }
        }
    }

    private func deltaView(_ deltaInt: Int) -> some View {
        ZStack {
            let deltaConverted = units == .mmolL ? deltaInt.asMmolL : Decimal(deltaInt)
            let string = deltaFormatter.string(from: deltaConverted as NSNumber) ?? ""
            let offset: CGFloat = -7

            Text(string)
                .font(.callout).foregroundStyle(.secondary)
                .offset(x: offset, y: 10)
        }
        .dynamicTypeSize(DynamicTypeSize.medium ... DynamicTypeSize.large)
        .frame(maxHeight: .infinity, alignment: .center).offset(x: 110.5, y: -9)
    }

    private var adjustments: (degree: Double, x: CGFloat, y: CGFloat) {
        let yOffset: CGFloat = 17
        guard let direction = recentGlucose?.direction else {
            return (90, 0, yOffset)
        }
        switch direction {
        case .doubleUp,
             .singleUp,
             .tripleUp:
            return (0, 0, yOffset)
        case .fortyFiveUp:
            return (45, 0, yOffset)
        case .flat:
            return (90, 0, yOffset)
        case .fortyFiveDown:
            return (135, 0, yOffset)
        case .doubleDown,
             .singleDown,
             .tripleDown:
            return (180, 0, yOffset)
        case .none,
             .notComputable,
             .rateOutOfRange:
            return (90, 0, yOffset)
        }
    }

    private func direction(degree: Double) -> (x: CGFloat, y: CGFloat) {
        switch degree {
        case 0:
            return (0, -2)
        case 45:
            return (1, -2)
        case 90:
            return (2, 0)
        case 135:
            return (1, 2)
        case 180:
            return (0, 2)
        default:
            return (2, 0)
        }
    }

    private func glucoseText(_ string: String) -> any View {
        ZStack {
            let decimal = string.components(separatedBy: Self.decimalString)
            if decimal.count > 1 {
                HStack(spacing: 0) {
                    Text(decimal[0]).font(scrolling ? .glucoseSmallFont : .glucoseFont)
                    Text(Self.decimalString).font(.system(size: !scrolling ? 28 : 14).weight(.semibold)).baselineOffset(-10)
                    Text(decimal[1]).font(.system(size: !scrolling ? 28 : 18)).baselineOffset(!scrolling ? -10 : -4)
                }
                .tracking(-1)
                .offset(x: -2, y: 14)
                .foregroundColor(alwaysUseColors ? colorOfGlucose : appUIState.glucoseAlarm == nil ? .primary : .loopRed)
            } else {
                Text(string)
                    .font(scrolling ? .glucoseSmallFont : .glucoseFontMdDl.width(.condensed)) // .tracking(-2)
                    .foregroundColor(alwaysUseColors ? colorOfGlucose : appUIState.glucoseAlarm == nil ? .primary : .loopRed)
                    .offset(x: string.count > 2 ? -1 : -1, y: 16)
            }
        }
        .offset(y: scrolling ? 3 : 0)
    }

    private var glucoseDrop: some View {
        let adjust = adjustments
        let degree = adjustments.degree
        let shadowDirection = direction(degree: degree)
        return Image("glucoseDrops")
            .resizable()
            .frame(width: !scrolling ? 140 : 80, height: !scrolling ? 140 : 80).rotationEffect(.degrees(degree))
            .animation(.bouncy(duration: 1, extraBounce: 0.2), value: degree)
            .offset(x: adjust.x, y: adjust.y)
            .shadow(radius: 3, x: shadowDirection.x, y: shadowDirection.y)
    }

    private var colorOfGlucose: Color {
        let whichGlucose = recentGlucose?.glucose ?? 0
        guard lowGlucose < highGlucose else { return .primary }

        switch whichGlucose {
        case 0 ..< Int(lowGlucose):
            return .loopRed
        case Int(lowGlucose) ..< Int(highGlucose):
            return .loopGreen
        case Int(highGlucose)...:
            return .loopYellow
        default:
            return .loopYellow
        }
    }
}

/// The header's CGM element: the sensor ring, the source's name where there is no sensor session, or "No CGM".
/// It is a view of its own, so that its tap is its own and not the glucose value's.
struct HomeCGMView: View {
    let cgmInfo: CgmDisplayInfo?
    let cgmStatus: CgmDisplayStatus?
    /// the session start the last glucose record carries
    let recentGlucoseSessionStart: Date?
    let displaySAGE: Bool
    let displayExpiration: Bool
    /// the sensor's lifetime in seconds
    let sensorLifetime: TimeInterval
    let timerDate: Date
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    enum Element: Equatable {
        case noCGM
        /// a CGM without a sensor session (Nightscout, an app group source, a sensor not started yet): its name
        case label(String)
        /// seconds since the session's start and until its end, neither ever negative
        case sensor(age: TimeInterval, remaining: TimeInterval)
        /// a sensor session while both "Display Sensor Age" and "Display Sensor Time Remaining" are off
        case hidden
    }

    static let secondsOfDay: TimeInterval = 86400

    /// The CGM's own lifetime (seconds) when it knows one, the "Sensor Life-Span" setting (days) otherwise.
    static func sensorLifetime(cgmLifetime: TimeInterval?, settingsDays: Double) -> TimeInterval {
        if let cgmLifetime, cgmLifetime > 0 { return cgmLifetime }
        return max(settingsDays, 0) * secondsOfDay
    }

    /// The manager's current session comes first: a new sensor shows before its first reading. The last glucose
    /// record's session stands in only for a CGM that knows its sensor's lifetime (a Dexcom before the first
    /// reading after a launch): that record may be one of a CGM that has been replaced since.
    static func sessionStart(status: CgmDisplayStatus?, recentGlucoseSessionStart: Date?) -> Date? {
        guard let status else { return nil }
        if let sessionStart = status.sessionStartDate { return sessionStart }
        return status.sensorDays != nil ? recentGlucoseSessionStart : nil
    }

    /// `cgmLabel`: the configured CGM's label, nil without a CGM.
    static func element(
        cgmLabel: String?,
        sessionStart: Date?,
        lifetime: TimeInterval,
        showsRing: Bool,
        now: Date
    ) -> Element {
        guard let cgmLabel else { return .noCGM }
        guard let sessionStart else { return .label(cgmLabel) }
        guard showsRing else { return .hidden }
        // a session that starts in the future (a sensor warming up) is a new one, and an overdue one has nothing left
        let age = max(now.timeIntervalSince(sessionStart), 0)
        return .sensor(age: age, remaining: max(lifetime - age, 0))
    }

    /// A name short enough for the header's corner.
    static func label(name: String, identifier: String, statisticsIdentifier: String?) -> String {
        if statisticsIdentifier == "nightscout" {
            return NSLocalizedString("NS CGM", comment: "Home header, short name of the Nightscout CGM source")
        }
        if identifier == "AppGroupCGM" {
            return NSLocalizedString("App CGM", comment: "Home header, short name of the Shared App Group CGM source")
        }
        return name
    }

    private static let remainingTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let remainingTimeFormatterDays: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var element: Element {
        Self.element(
            cgmLabel: cgmInfo.map {
                Self.label(name: $0.name, identifier: $0.identifier, statisticsIdentifier: $0.identifierForStatistics)
            },
            sessionStart: Self.sessionStart(status: cgmStatus, recentGlucoseSessionStart: recentGlucoseSessionStart),
            lifetime: sensorLifetime,
            showsRing: displaySAGE || displayExpiration,
            now: timerDate
        )
    }

    var body: some View {
        let element = self.element
        if element != .hidden {
            content(element)
                .font(.footnote)
                .dynamicTypeSize(DynamicTypeSize.medium ... DynamicTypeSize.large)
                .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        }
    }

    @ViewBuilder private func content(_ element: Element) -> some View {
        switch element {
        case .hidden:
            EmptyView()
        case .noCGM:
            nameLabel(NSLocalizedString("No CGM", comment: "Home header, no CGM is configured"))
        case let .label(name):
            nameLabel(name)
        case let .sensor(age, remaining):
            ring(age: age, remaining: remaining)
        }
    }

    private func nameLabel(_ text: String) -> some View {
        Text(text)
            .font(.statusFont)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 110, alignment: .trailing)
    }

    private func ring(age: TimeInterval, remaining: TimeInterval) -> some View {
        let colour = colorScheme == .light ? Color.black : Color.white
        let lineColour: Color = remaining <= Self.secondsOfDay ? Color.red.opacity(0.9) :
            remaining <= Self.secondsOfDay * 2 ? Color.orange : Color.white
        let shown = displayExpiration ? remaining : age
        let formatter = shown < Self.secondsOfDay ? Self.remainingTimeFormatter : Self.remainingTimeFormatterDays

        // the ring's fill is remaining / age: at least a second of age keeps it finite
        return Sage(amount: max(age, 1), expiration: remaining, lineColour: lineColour, sensordays: sensorLifetime)
            .frame(width: 36, height: 36)
            .overlay {
                Text((formatter.string(from: shown) ?? "").replacingOccurrences(of: ",", with: " "))
                    .foregroundStyle(colour)
                    .fontWeight(colorScheme == .dark ? .semibold : .regular)
            }
    }
}

/// A header device element (the CGM's, the pump's) with its manager's status highlight: the highlight's icon to the
/// left of the element. While there is a highlight, a tap on the element or the icon shows its message with a button
/// to the device's settings; without one the tap opens the settings.
struct HomeDeviceStatusView<Content: View>: View {
    let highlight: DeviceStatusHighlightDisplay?
    var alignment: VerticalAlignment = .center
    /// moves the icon down to the element's middle, where the element is not centered in its own frame
    var iconOffsetY: CGFloat = 0
    let settingsTitle: String
    let openSettings: () -> Void
    /// the element; it gets the tap's action for a tap target of its own
    @ViewBuilder let content: (_ tap: @escaping () -> Void) -> Content

    @State private var showsStatus = false
    @State private var opensSettingsOnDismiss = false

    private func tap() {
        if highlight == nil {
            openSettings()
        } else {
            showsStatus = true
        }
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 4) {
            if let highlight {
                Image(systemName: highlight.symbolName)
                    .font(.system(size: 18))
                    .foregroundStyle(highlight.level.color)
                    .offset(y: iconOffsetY)
            }
            content(tap)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .popover(isPresented: $showsStatus) {
            VStack(spacing: 12) {
                Text(highlight?.message ?? "")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(settingsTitle) {
                    // the settings are a modal: it is presented once the popover is gone
                    opensSettingsOnDismiss = true
                    showsStatus = false
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: 260)
            .presentationCompactAdaptation(.popover)
            .onDisappear {
                guard opensSettingsOnDismiss else { return }
                opensSettingsOnDismiss = false
                openSettings()
            }
        }
        .onChange(of: highlight == nil) { _, none in
            // the status is gone: so is its message
            if none { showsStatus = false }
        }
    }
}

extension DeviceStatusHighlightLevel {
    var color: Color {
        switch self {
        case .normal: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }
}
