import Foundation

/// The display rules of Statistics: the values come from the service in mg/dL and are only formatted here.
@MainActor enum StatsFormatting {
    private static let mgdLFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// configured like the header's (`CurrentGlucoseView.mmolLFormatter`), which `StatsBands.mmolDisplay` follows
    private static let mmolLFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let percentA1cFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let wholeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    // MARK: - Glucose

    /// An integer mg/dL value (a band edge): 0 decimals in mg/dL, the `mmolDisplay` rule in mmol/L.
    static func glucose(_ mgdl: Int, units: GlucoseUnits) -> String {
        switch units {
        case .mgdL:
            return mgdLFormatter.string(from: mgdl as NSNumber) ?? "\(mgdl)"
        case .mmolL:
            return mmol(StatsBands.mmolDisplay(mgdl))
        }
    }

    /// A mean or an SD: 0 decimals in mg/dL, the `mmolDisplay` rule in mmol/L.
    static func glucose(_ mgdl: Double, units: GlucoseUnits) -> String {
        switch units {
        case .mgdL:
            return mgdLFormatter.string(from: mgdl.rounded() as NSNumber) ?? "\(Int(mgdl.rounded()))"
        case .mmolL:
            return mmol(StatsBands.mmolDisplay(decimal: Decimal(mgdl)))
        }
    }

    /// A value already in the units shown (a Weekly mean as shown, its Δ, a level of its chart): as a whole number in
    /// mg/dL, to one decimal in mmol/L.
    static func glucose(shown value: Decimal, units: GlucoseUnits) -> String {
        switch units {
        case .mgdL:
            return mgdLFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
        case .mmolL:
            return mmol(value)
        }
    }

    static func unit(_ units: GlucoseUnits) -> String {
        units.rawValue
    }

    /// "70–145", or a single value for a one-value range.
    static func range(_ range: ClosedRange<Int>, units: GlucoseUnits) -> String {
        let lower = glucose(range.lowerBound, units: units)
        guard range.upperBound != range.lowerBound else { return lower }
        return lower + "–" + glucose(range.upperBound, units: units)
    }

    // MARK: - Bands

    static func name(_ band: GlucoseBand) -> String {
        switch band {
        case .veryLow: return NSLocalizedString("Very low", comment: "Statistics glucose band")
        case .low: return NSLocalizedString("Low", comment: "Statistics glucose band")
        case .inRange: return NSLocalizedString("In range", comment: "Statistics glucose band")
        case .high: return NSLocalizedString("High", comment: "Statistics glucose band")
        case .veryHigh: return NSLocalizedString("Very high", comment: "Statistics glucose band")
        }
    }

    /// "< 54", "54–69", "70–145", "146–250", "> 250"; nil for a zero-width band (it is hidden).
    static func label(_ band: GlucoseBand, bands: StatsBands, units: GlucoseUnits) -> String? {
        switch band {
        case .veryLow:
            return "< " + glucose(StatsBands.veryLowBelow, units: units)
        case .veryHigh:
            return "> " + glucose(StatsBands.veryHighAbove, units: units)
        case .high,
             .inRange,
             .low:
            return bands.range(of: band).map { range($0, units: units) }
        }
    }

    /// The rows of `visible` (in its order): each band's name, range and `percent`.
    static func bandRows(
        _ visible: [GlucoseBand],
        bands: StatsBands,
        units: GlucoseUnits,
        percent: (GlucoseBand) -> String
    ) -> [StatsBandRow] {
        visible.map { band in
            StatsBandRow(
                band: band,
                name: name(band),
                range: label(band, bands: bands, units: units) ?? "",
                percent: percent(band)
            )
        }
    }

    /// "70–145 mg/dL": the in-range band with its unit
    static func inRangeLabel(bands: StatsBands, units: GlucoseUnits) -> String {
        (label(.inRange, bands: bands, units: units) ?? "") + " " + unit(units)
    }

    /// "TIR 70–180"
    static func tirTitle(bands: StatsBands, units: GlucoseUnits) -> String {
        String(
            format: NSLocalizedString("TIR %@", comment: "Statistics, time in 70-180"),
            range(bands.tirRange, units: units)
        )
    }

    /// "TITR 70–140"
    static func titrTitle(bands: StatsBands, units: GlucoseUnits) -> String {
        String(
            format: NSLocalizedString("TITR %@", comment: "Statistics, time in 70-140"),
            range(bands.titrRange, units: units)
        )
    }

    // MARK: - Percentages and durations

    /// A band's largest-remainder percent; a nonzero band that rounds to 0 is "<1%".
    static func percent(_ band: GlucoseBand, of shares: some BandSharesProviding) -> String {
        percentNumber(band, of: shares) + "%"
    }

    /// `percent(_:of:)` without the sign, for the headline that sets it apart: "<1", "62".
    static func percentNumber(_ band: GlucoseBand, of shares: some BandSharesProviding) -> String {
        shares.isBelowOnePercent(band) ? "<1" : "\(shares.percent(band))"
    }

    static func percent(_ value: Int) -> String {
        "\(value)%"
    }

    /// A largest-remainder percent outside a summary (a day of the Trace's strip): "<1%" when it rounded to 0.
    static func percent(_ value: Int, belowOne: Bool) -> String {
        belowOne ? "<1%" : percent(value)
    }

    /// "5–95%", "25–75%": a percentile band of a profile's legend (the AGP's, the IOB's); nonisolated as `label`
    nonisolated static func percentileBand(_ lower: Int, _ upper: Int) -> String {
        String(
            format: NSLocalizedString(
                "%1$d–%2$d%%",
                comment: "Statistics AGP legend: a percentile band, the lower and the upper percentile"
            ),
            lower,
            upper
        )
    }

    /// A fraction (0.62) as a whole percent, rounded: "62%".
    static func percent(fraction: Double) -> String {
        percent(Int((fraction * 100).rounded()))
    }

    /// The time a fraction of a day is: "0 m", "<1 m", "N m", "H h MM m".
    static func perDay(_ fraction: Double) -> String {
        duration(minutes: fraction * 24 * 60)
    }

    static func duration(minutes: Double) -> String {
        guard minutes > 0 else { return NSLocalizedString("0 m", comment: "Statistics duration") }
        guard minutes >= 1 else { return NSLocalizedString("<1 m", comment: "Statistics duration") }
        let (hours, rest) = hoursAndMinutes(minutes)
        guard hours > 0 else {
            return String(format: NSLocalizedString("%d m", comment: "Statistics duration, minutes"), rest)
        }
        return String(format: NSLocalizedString("%d h %02d m", comment: "Statistics duration, hours and minutes"), hours, rest)
    }

    /// `duration(minutes:)` of a number of seconds
    static func duration(seconds: Double) -> String {
        duration(minutes: seconds / 60)
    }

    /// whole hours and the minutes rounded, 60 minutes carried into the hours
    private static func hoursAndMinutes(_ minutes: Double) -> (hours: Int, minutes: Int) {
        var hours = Int(minutes / 60)
        var rest = Int((minutes - Double(hours) * 60).rounded())
        if rest == 60 {
            hours += 1
            rest = 0
        }
        return (hours, rest)
    }

    // MARK: - A1c estimates

    /// GMI or eA1c: 1 decimal in %, 0 decimals in mmol/mol (IFCC).
    static func a1c(_ percent: Double?, unit: HbA1cUnit) -> String {
        guard let percent else { return "–" }
        switch unit {
        case .percent:
            return percentA1cFormatter.string(from: percent as NSNumber) ?? ""
        case .mmolPerMol:
            return wholeFormatter.string(from: GlucoseStatsEngine.ifcc(fromPercent: percent) as NSNumber) ?? ""
        }
    }

    static func a1cUnit(_ unit: HbA1cUnit) -> String {
        switch unit {
        case .percent: return "%"
        case .mmolPerMol: return "mmol/mol"
        }
    }

    // MARK: - Periods

    /// Nonisolated: Home's meal card is formatted off the main actor (`HomeMealsCard.Content`).
    nonisolated static func label(_ period: StatsPeriod) -> String {
        switch period {
        case .today: return NSLocalizedString("Today", comment: "")
        case .last24h: return NSLocalizedString("24 h", comment: "Statistics period")
        case .days7: return NSLocalizedString("7 d", comment: "Statistics period")
        case .days14: return NSLocalizedString("14 d", comment: "Statistics period")
        case .days30: return NSLocalizedString("30 d", comment: "Statistics period")
        case .days90: return NSLocalizedString("90 d", comment: "Statistics period")
        case .weeks5: return NSLocalizedString("1 mo", comment: "Statistics period, 5 weeks")
        case .weeks13: return NSLocalizedString("3 mo", comment: "Statistics period, 13 weeks")
        case .weeks4,
             .weeks8: return weeksLabel(period)
        }
    }

    /// "4 wk", "13 wk": a weekly period by its weeks (By weekday's chips, `StatsTab.weekday`); nonisolated as `label`.
    nonisolated static func weeksLabel(_ period: StatsPeriod) -> String {
        guard let weeks = period.weekCount else { return label(period) }
        return String(format: NSLocalizedString("%d wk", comment: "Statistics period: a number of whole weeks"), weeks)
    }

    /// "Today, 00:00–14:35", "29 Oct 14:35 – now", "17 Oct – 30 Oct". Today ends at the window's end, never later
    /// than now (floored to the minute).
    static func dateRange(_ window: DateInterval, period: StatsPeriod, now: Date = Date()) -> String {
        switch period {
        case .today:
            let end = min(window.end, now)
            let endMinute = Calendar.current.dateInterval(of: .minute, for: end)?.start ?? end
            return String(
                format: NSLocalizedString("Today, %@–%@", comment: "Statistics date range of Today"),
                window.start.formatted(date: .omitted, time: .shortened),
                endMinute.formatted(date: .omitted, time: .shortened)
            )
        case .last24h:
            return String(
                format: NSLocalizedString("%@ – now", comment: "Statistics date range of the last 24 hours"),
                window.start.formatted(.dateTime.day().month(.abbreviated)) + " " +
                    window.start.formatted(date: .omitted, time: .shortened)
            )
        case .days7,
             .days14,
             .days30,
             .days90,
             .weeks4,
             .weeks5,
             .weeks8,
             .weeks13:
            // the period's last day: today, also when it has no readings yet; By weekday's window (whole weeks to
            // yesterday, `GlucoseStatsEngine.weekdayDays`) has as many days from its start, so its last one, yesterday
            let days = period.calendarDayCount ?? 1
            let last = Calendar.current.date(byAdding: .day, value: days - 1, to: window.start) ?? window.end
            return String(
                format: NSLocalizedString("%@ – %@", comment: "Statistics date range, first and last day"),
                window.start.formatted(.dateTime.day().month(.abbreviated)),
                last.formatted(.dateTime.day().month(.abbreviated))
            )
        }
    }

    /// "12 of 14"
    static func days(_ daysWithData: Int, of calendarDays: Int) -> String {
        String(format: NSLocalizedString("%d of %d", comment: "Statistics days with data"), daysWithData, calendarDays)
    }

    /// The selected hour's subtitle of a By hour chart: "30 days · 12 hours of data", "1 day · 3 hours of data": the
    /// days averaged, and the hours of data of the hour (rounded). The 1-day forms are Insulin by hour's (By hour offers
    /// 7 days or more), so they keep that view's keys and comments. Nonisolated as `label`.
    nonisolated static func hourDataNote(hours: Double, days: Int) -> String {
        let rounded = Int(hours.rounded())
        if days == 1 {
            if hours > 0, rounded == 0 {
                return NSLocalizedString(
                    "1 day · less than 1 hour of data",
                    comment: "Statistics Insulin by hour: one day averaged, the hour's data"
                )
            }
            if rounded == 1 {
                return NSLocalizedString(
                    "1 day · 1 hour of data",
                    comment: "Statistics Insulin by hour: one day averaged, the hour's data"
                )
            }
            return String(
                format: NSLocalizedString(
                    "1 day · %d hours of data",
                    comment: "Statistics Insulin by hour: one day averaged, the hours of data of the hour"
                ),
                rounded
            )
        }
        if hours > 0, rounded == 0 {
            return String(
                format: NSLocalizedString(
                    "%d days · less than 1 hour of data",
                    comment: "Statistics By hour: the days of the period, the hour's data"
                ),
                days
            )
        }
        if rounded == 1 {
            return String(
                format: NSLocalizedString(
                    "%d days · 1 hour of data",
                    comment: "Statistics By hour: the days of the period, the hour's data"
                ),
                days
            )
        }
        return String(
            format: NSLocalizedString(
                "%1$d days · %2$d hours of data",
                comment: "Statistics By hour: the days of the period, the hours of data of the hour"
            ),
            days,
            rounded
        )
    }

    // MARK: - Limited data

    // Why a number is provisional, as its marker explains it (`LimitedDataMarker`): the rule, never the counts (the
    // coverage and the days with data are shown beside it, or add nothing).

    /// CGM coverage below 70% (`GlucoseSummary.isLimited`); nil when it isn't
    static func coverageNote(_ summary: GlucoseSummary) -> String? {
        summary.isLimited
            ? NSLocalizedString(
                "CGM readings cover less than 70% of this period, so these numbers may not represent it.",
                comment: "Statistics limited data: the CGM coverage is below 70%"
            )
            : nil
    }

    /// GMI and eA1c from fewer than 14 days with readings (`GlucoseSummary.a1cNeedsMoreDays`); nil when not, and
    /// without readings (the estimates are dashes)
    static func a1cNote(_ summary: GlucoseSummary) -> String? {
        summary.a1cNeedsMoreDays && summary.mean != nil
            ? NSLocalizedString(
                "GMI and eA1c are meant for 14 or more days with readings; this period has fewer.",
                comment: "Statistics limited data: the A1c estimates from fewer than 14 days"
            )
            : nil
    }

    /// The AGP's (and the usual day's): fewer than 14 days with readings, the coverage below 70%, or both
    /// (`GlucoseStatsEngine.agpIsLimited`); nil when it isn't limited
    static func profileNote(_ summary: GlucoseSummary) -> String? {
        guard GlucoseStatsEngine.agpIsLimited(summary) else { return nil }
        let fewDays = summary.daysWithData < GlucoseStatsEngine.agpMinimumDays
            ? NSLocalizedString(
                "A glucose profile is meant for 14 or more days with readings; this period has fewer.",
                comment: "Statistics limited data: the AGP from fewer than 14 days"
            )
            : nil
        return [fewDays, coverageNote(summary)].compactMap { $0 }.joined(separator: " ")
    }

    private static func mmol(_ value: Decimal) -> String {
        mmolLFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}
