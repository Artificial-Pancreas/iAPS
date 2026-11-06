import Foundation

/// A basal schedule from Nightscout, in effect from `date` until the next one (standard units: no uploader's profile
/// carries a concentration).
struct NightscoutBasalSchedule: Sendable, Equatable {
    let date: Date
    let entries: [BasalProfileEntry]
    /// `enteredBy` / `app` of a profile document, or "Profile Switch"
    let uploader: String?
    let timeZone: String?
}

/// A Nightscout profile document as the insulin backfill reads it: the basal of each named profile, leniently (Loop
/// writes some numbers as strings, AAPS dates with seven fractional digits). Documents of the profile collection
/// that aren't profiles (iAPS posts its Preferences there) have no usable basal and map to no schedule.
struct NightscoutProfileDocument: Decodable, Sendable, Equatable {
    var id: String?
    /// `startDate`; else `mills`, API v3's `date`, `created_at`
    var startDate: Date?
    var defaultProfile: String?
    var store: [String: NightscoutProfileBasal] = [:]
    var enteredBy: String?
    /// API v3's uploader (AAPS: "AAPS")
    var app: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case identifier
        case startDate
        case mills
        case date
        case createdAt = "created_at"
        case defaultProfile
        case store
        case enteredBy
        case app
    }

    init(
        id: String? = nil,
        startDate: Date?,
        defaultProfile: String?,
        store: [String: NightscoutProfileBasal],
        enteredBy: String? = nil,
        app: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.defaultProfile = defaultProfile
        self.store = store
        self.enteredBy = enteredBy
        self.app = app
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.nightscoutString(.id) ?? container.nightscoutString(.identifier)
        startDate = container.nightscoutDate(.startDate) ?? container.nightscoutDate(.mills) ??
            container.nightscoutDate(.date) ?? container.nightscoutDate(.createdAt)
        defaultProfile = container.nightscoutString(.defaultProfile)
        enteredBy = container.nightscoutString(.enteredBy)
        app = container.nightscoutString(.app)
        if let profiles = try? container.nestedContainer(keyedBy: AnyKey.self, forKey: .store) {
            for key in profiles.allKeys {
                if let profile = try? profiles.decode(NightscoutProfileBasal.self, forKey: key) {
                    store[key.stringValue] = profile
                }
            }
        }
    }

    var uploader: String? { enteredBy ?? app }

    /// What the pager deduplicates by: the document's id.
    var pagingKey: String {
        id ?? "\(startDate?.timeIntervalSince1970 ?? 0)|\(defaultProfile ?? "")|\(uploader ?? "")"
    }

    /// The default profile (iAPS/Trio "default", Loop "Default"; a store of one profile: that one).
    var defaultBasal: NightscoutProfileBasal? {
        if let name = defaultProfile, let profile = store[name] {
            return profile
        }
        return store.count == 1 ? store.values.first : nil
    }

    /// The default profile's basal schedule; nil when there is none or it is unusable.
    func basalSchedule() -> [BasalProfileEntry]? {
        defaultBasal?.schedule()
    }

    /// The basal schedule history of the fetched documents and AAPS profile switches, oldest first, consecutive
    /// equal schedules as one (from the earliest):
    /// - a document's schedule takes effect at its `startDate` (iAPS/Trio: the upload time; Loop and AAPS: the
    ///   change). Unusable schedules and non-profile documents are skipped.
    /// - an uploader with any profile switch (AAPS) gets its schedules from the switches, not its documents (a
    ///   document is a library of profiles): the switch's `profileJson`, or the named profile of its newest document
    ///   at or before the switch; times `percentage / 100`; shifted by `timeshift` (AAPS's sense: +2 h makes 08:00
    ///   run the profile's 06:00 rate). Resolved as AAPS does (`switchSchedules`): the newest switch still running
    ///   is in effect, so a temporary one ends into whatever runs then.
    static func basalSchedules(
        documents: [NightscoutProfileDocument],
        switches: [NightscoutInsulinTreatment]
    ) -> [NightscoutBasalSchedule] {
        let switches = switches
            .filter { $0.isValid != false && $0.eventType == "Profile Switch" && $0.createdAt != nil }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        let switchUploaders = Set(switches.map { $0.uploader ?? "" })
        let aapsSwitches = switches.contains { NightscoutInsulinTreatment.isAAPS($0.uploader) }
        let documents = documents
            .filter { $0.startDate != nil }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        // the documents of an uploader with switches are its library, not its schedule: AAPS v1 documents carry no
        // uploader at all (its switches say "openaps://AndroidAPS")
        func isLibrary(_ document: NightscoutProfileDocument) -> Bool {
            switchUploaders.contains(document.uploader ?? "") ||
                (aapsSwitches && (document.uploader == nil || NightscoutInsulinTreatment.isAAPS(document.uploader)))
        }

        var schedules: [NightscoutBasalSchedule] = documents.compactMap { document in
            guard !isLibrary(document),
                  let date = document.startDate,
                  let entries = document.basalSchedule()
            else { return nil }
            return NightscoutBasalSchedule(
                date: date,
                entries: entries,
                uploader: document.uploader,
                timeZone: document.defaultBasal?.timezone
            )
        }
        schedules += switchSchedules(switches, documents: documents, library: documents.filter(isLibrary))

        var collapsed: [NightscoutBasalSchedule] = []
        for schedule in schedules.sorted(by: { $0.date < $1.date }) {
            if let last = collapsed.last,
               BasalScheduleRecordValue.fingerprint(last.entries) == BasalScheduleRecordValue.fingerprint(schedule.entries)
            {
                continue
            }
            collapsed.append(schedule)
        }
        return collapsed
    }

    /// The schedules the switches give, as AAPS resolves them: at any time the newest switch still running (a
    /// permanent one runs until the next; a temporary one until its end) is in effect. So a record at every switch
    /// start and every temporary end, nested temporaries included. A switch whose profile can't be found is left
    /// out (it never hides the end of one before it). Where none runs (a temporary ended with no permanent one
    /// known before it): the switching uploader's newest document at that time (its default profile), else nothing
    /// is known, and the temporaries before that point are left out too (their end would never come).
    private static func switchSchedules(
        _ switches: [NightscoutInsulinTreatment],
        documents: [NightscoutProfileDocument],
        library: [NightscoutProfileDocument]
    ) -> [NightscoutBasalSchedule] {
        struct Span {
            let start: Date
            /// nil: permanent
            let end: Date?
            let entries: [BasalProfileEntry]
            let timeZone: String?
        }
        let spans: [Span] = switches.compactMap { profileSwitch in
            guard let start = profileSwitch.createdAt,
                  let base = switchBase(profileSwitch, documents: documents),
                  let entries = adjusted(base.entries, percentage: profileSwitch.percentage, timeshift: profileSwitch.timeshift)
            else { return nil }
            let minutes = profileSwitch.durationMinutes
            return Span(
                start: start,
                end: minutes > 0 ? start.addingTimeInterval(.minutes(minutes)) : nil,
                entries: entries,
                timeZone: base.timeZone
            )
        }

        var schedules: [NightscoutBasalSchedule] = []
        for boundary in Set(spans.map(\.start) + spans.compactMap(\.end)).sorted() {
            let running = spans
                .filter { $0.start <= boundary && ($0.end.map { boundary < $0 } ?? true) }
                .max { $0.start < $1.start }
            if let running {
                schedules.append(NightscoutBasalSchedule(
                    date: boundary,
                    entries: running.entries,
                    uploader: "Profile Switch",
                    timeZone: running.timeZone
                ))
            } else if let document = library.last(where: { ($0.startDate ?? .distantFuture) <= boundary }),
                      let entries = document.basalSchedule()
            {
                schedules.append(NightscoutBasalSchedule(
                    date: boundary,
                    entries: entries,
                    uploader: document.uploader,
                    timeZone: document.defaultBasal?.timezone
                ))
            } else {
                schedules.removeAll()
            }
        }
        return schedules
    }

    /// The profile a switch runs at 100%: its `profileJson`, else its profile by name in the newest document at or
    /// before it (of its uploader, any if none).
    private static func switchBase(
        _ profileSwitch: NightscoutInsulinTreatment,
        documents: [NightscoutProfileDocument]
    ) -> (entries: [BasalProfileEntry], timeZone: String?)? {
        if let json = profileSwitch.profileJson,
           let profile = try? JSONDecoder().decode(NightscoutProfileBasal.self, from: Data(json.utf8)),
           let entries = profile.schedule()
        {
            return (entries, profile.timezone)
        }
        guard let date = profileSwitch.createdAt else { return nil }
        let names = [profileSwitch.originalProfileName, profileSwitch.profile].compactMap { $0 }
        let candidates = documents.filter { ($0.startDate ?? .distantFuture) <= date }
        let own = candidates.filter { $0.uploader == profileSwitch.uploader }
        for document in (own.isEmpty ? candidates : own).reversed() {
            for name in names {
                if let profile = document.store[name], let entries = profile.schedule() {
                    return (entries, profile.timezone)
                }
            }
        }
        return nil
    }

    /// A schedule times `percentage / 100` (rates to 3 decimals) and shifted by `timeshift`: AAPS sends milliseconds;
    /// a value within a day's hours is taken as hours. The rate at local time t is the profile's at t - shift.
    static func adjusted(_ entries: [BasalProfileEntry], percentage: Double?, timeshift: Double?) -> [BasalProfileEntry]? {
        let factor = (percentage ?? 100) / 100
        guard factor.isFinite, factor >= 0 else { return nil }
        let hours: Double = {
            guard let timeshift, timeshift.isFinite else { return 0 }
            return abs(timeshift) <= 24 ? timeshift : timeshift / 3_600_000
        }()
        let day = 24 * 60
        // within a day before the conversion: a huge value would overflow `Int`
        let shift = ((Int((hours * 60).truncatingRemainder(dividingBy: Double(day)).rounded()) % day) + day) % day
        let sorted = entries.sorted { $0.minutes < $1.minutes }
        guard sorted.first?.minutes == 0 else { return nil }

        func base(at minute: Int) -> Decimal {
            sorted.last { $0.minutes <= minute }?.rate ?? sorted[0].rate
        }

        let starts = Set(sorted.map { ($0.minutes + shift) % day } + [0]).sorted()
        var result: [BasalProfileEntry] = []
        for start in starts {
            let rate = NightscoutProfileBasal.rounded(Double(base(at: ((start - shift) % day + day) % day)) * factor)
            if let last = result.last, last.rate == rate { continue }
            result.append(BasalProfileEntry(
                start: String(format: "%02d:%02d:00", start / 60, start % 60),
                minutes: start,
                rate: rate
            ))
        }
        return result
    }
}

/// A named profile's basal (and its time zone) as Nightscout stores it: `[{time "HH:mm", value, timeAsSeconds}]`.
struct NightscoutProfileBasal: Decodable, Sendable, Equatable {
    struct Entry: Decodable, Sendable, Equatable {
        var time: String?
        var value: Double?
        var timeAsSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case time
            case value
            case timeAsSeconds
        }

        init(time: String?, value: Double?, timeAsSeconds: Double? = nil) {
            self.time = time
            self.value = value
            self.timeAsSeconds = timeAsSeconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = container.nightscoutString(.time)
            value = container.nightscoutDouble(.value)
            timeAsSeconds = container.nightscoutDouble(.timeAsSeconds)
        }
    }

    var basal: [Entry]?
    var timezone: String?

    enum CodingKeys: String, CodingKey {
        case basal
        case timezone
    }

    init(basal: [Entry]?, timezone: String? = nil) {
        self.basal = basal
        self.timezone = timezone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basal = try? container.decodeIfPresent([Entry].self, forKey: .basal)
        timezone = container.nightscoutString(.timezone)
    }

    /// The schedule as `basal_profile.json` holds it: `minutes` from `timeAsSeconds / 60`, else from `time`
    /// ("HH:mm"); `start` "HH:mm:00"; `rate` = `value` (to 3 decimals). Unusable, so nil: no entries, the first not
    /// at 00:00, times not strictly ascending or not within the day, a rate missing or negative, every rate 0.
    func schedule() -> [BasalProfileEntry]? {
        guard let basal, basal.isNotEmpty else { return nil }
        var entries: [BasalProfileEntry] = []
        for entry in basal {
            guard let minutes = Self.minutes(of: entry),
                  let value = entry.value, value.isFinite, value >= 0
            else { return nil }
            if let last = entries.last, minutes <= last.minutes {
                return nil
            }
            entries.append(BasalProfileEntry(
                start: String(format: "%02d:%02d:00", minutes / 60, minutes % 60),
                minutes: minutes,
                rate: Self.rounded(value)
            ))
        }
        guard entries.first?.minutes == 0, entries.contains(where: { $0.rate > 0 }) else { return nil }
        return entries
    }

    private static func minutes(of entry: Entry) -> Int? {
        if let seconds = entry.timeAsSeconds {
            // within the day before the conversion: a huge value would overflow `Int`
            guard (0 ... 86400).contains(seconds) else { return nil }
            let minutes = Int((seconds / 60).rounded())
            return (0 ..< 24 * 60).contains(minutes) ? minutes : nil
        }
        guard let time = entry.time else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count >= 2, let hours = Int(parts[0]), let minutes = Int(parts[1]),
              (0 ..< 24).contains(hours), (0 ..< 60).contains(minutes)
        else { return nil }
        return hours * 60 + minutes
    }

    /// To 3 decimals, as a Decimal that prints as it reads.
    static func rounded(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.3f", value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
    }
}

/// A coding key for a dictionary of unknown names (a profile store).
private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
