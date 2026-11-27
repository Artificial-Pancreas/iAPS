import Foundation

/// One query of the insulin backfill (`NightscoutAPI.fetchInsulinTreatments`), each paged on its own.
enum NightscoutInsulinQuery: Sendable, CaseIterable {
    /// `"Temp Basal"`: every uploader's temps (Loop's suspends and AAPS's pump suspends are rate-0 temps)
    case tempBasals
    /// `insulin > 0`, any eventType: the server casts `insulin` numerically (`lib/server/treatments.js` walker)
    case boluses
    /// AAPS's extended boluses (the insulin is in `enteredinsulin`)
    case comboBoluses
    /// Trio's `"Note"` "PumpSuspend" / "PumpResume"
    case suspendNotes
    case resumeNotes
    /// AAPS's `"Profile Switch"`: the schedule history
    case profileSwitches
    /// `"Site Change"`, every uploader's: a pod's, patch's or set's change (the pump sessions)
    case siteChanges
    /// `"Announcement"` with `notes` starting "Alarm": iAPS's pump alarms, a pod's or patch's end. The server matches
    /// the prefix (v1 passes `find[]` to Mongo as it is: `$regex`), the titles are matched here
    /// (`NightscoutInsulinTreatment.alarm()`).
    case announcements

    /// The queries whose treatments become insulin records (the profile switches are the schedules').
    static let insulin: [NightscoutInsulinQuery] = [.tempBasals, .boluses, .comboBoluses, .suspendNotes, .resumeNotes]
    /// The queries whose treatments become the Nightscout pump sessions (`NightscoutSessionsInput`).
    static let sessions: [NightscoutInsulinQuery] = [.siteChanges, .announcements]

    var queryItems: [URLQueryItem] {
        switch self {
        case .tempBasals:
            [URLQueryItem(name: "find[eventType]", value: "Temp Basal")]
        case .boluses:
            [URLQueryItem(name: "find[insulin][$gt]", value: "0")]
        case .comboBoluses:
            [URLQueryItem(name: "find[eventType]", value: "Combo Bolus")]
        case .suspendNotes:
            [URLQueryItem(name: "find[eventType]", value: "Note"), URLQueryItem(name: "find[notes]", value: "PumpSuspend")]
        case .resumeNotes:
            [URLQueryItem(name: "find[eventType]", value: "Note"), URLQueryItem(name: "find[notes]", value: "PumpResume")]
        case .profileSwitches:
            [URLQueryItem(name: "find[eventType]", value: "Profile Switch")]
        case .siteChanges:
            [URLQueryItem(name: "find[eventType]", value: "Site Change")]
        case .announcements:
            [
                URLQueryItem(name: "find[eventType]", value: "Announcement"),
                URLQueryItem(name: "find[notes][$regex]", value: "^Alarm")
            ]
        }
    }
}

/// A Nightscout treatment as the insulin backfill reads it: only the fields any uploader's insulin needs, every one
/// optional and read leniently (a number may come as a string, a date as ISO text or epoch ms). Not
/// `NigtscoutTreatment`, whose `EventType` rejects unknown values.
struct NightscoutInsulinTreatment: Decodable, Sendable, Equatable {
    var id: String?
    /// API v3's id
    var identifier: String?
    var eventType: String?
    /// `created_at`; else API v3's `date` (epoch ms), else Loop's `timestamp`
    var createdAt: Date?
    var insulin: Double?
    /// AAPS Combo Bolus: the extended bolus's insulin
    var enteredinsulin: Double?
    /// minutes
    var duration: Double?
    /// AAPS: the exact duration (its `duration` is floored to whole minutes)
    var durationInMilliseconds: Double?
    var absolute: Double?
    var rate: Double?
    var percent: Double?
    var isSMB: Bool?
    /// AAPS: `NORMAL` / `SMB` / `PRIMING` (boluses), `NORMAL` / `PUMP_SUSPEND` / `FAKE_EXTENDED` / ... (temps)
    var type: String?
    /// Loop: an automatic bolus
    var automatic: Bool?
    var reason: String?
    var notes: String?
    /// AAPS (API v3): false for a soft-deleted document, which a v1 GET still returns
    var isValid: Bool?
    /// iAPS and older Trio nest the pump history event: `bolus.isSMB`
    var bolusIsSMB: Bool?
    /// iAPS: `raw_rate.deliveredUnits`, the pump's delivered units of a finished temp
    var deliveredUnits: Double?
    var enteredBy: String?
    /// API v3's uploader (AAPS: "AAPS")
    var app: String?
    /// AAPS Combo Bolus: delivered as a `FAKE_EXTENDED` temp basal, which carries its insulin
    var isEmulatingTempBasal: Bool?
    /// Profile Switch: the (customized) profile name
    var profile: String?
    var originalProfileName: String?
    /// Profile Switch: the profile as a JSON string (AAPS: at 100%, not shifted)
    var profileJson: String?
    var percentage: Double?
    /// Profile Switch: AAPS sends milliseconds (Nightscout's own code assumes hours)
    var timeshift: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case identifier
        case eventType
        case createdAt = "created_at"
        case date
        case timestamp
        case insulin
        case enteredinsulin
        case duration
        case durationInMilliseconds
        case absolute
        case rate
        case percent
        case isSMB
        case type
        case automatic
        case reason
        case notes
        case isValid
        case bolus
        case rawRate = "raw_rate"
        case enteredBy
        case app
        case isEmulatingTempBasal
        case profile
        case originalProfileName
        case profileJson
        case percentage
        case timeshift
    }

    private enum NestedKeys: String, CodingKey {
        case isSMB
        case deliveredUnits
    }

    init(
        id: String? = nil,
        eventType: String?,
        createdAt: Date?,
        insulin: Double? = nil,
        duration: Double? = nil,
        absolute: Double? = nil,
        rate: Double? = nil
    ) {
        self.id = id
        self.eventType = eventType
        self.createdAt = createdAt
        self.insulin = insulin
        self.duration = duration
        self.absolute = absolute
        self.rate = rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.nightscoutString(.id)
        identifier = container.nightscoutString(.identifier)
        eventType = container.nightscoutString(.eventType)
        createdAt = container.nightscoutDate(.createdAt) ?? container.nightscoutDate(.date) ??
            container.nightscoutDate(.timestamp)
        insulin = container.nightscoutDouble(.insulin)
        enteredinsulin = container.nightscoutDouble(.enteredinsulin)
        duration = container.nightscoutDouble(.duration)
        durationInMilliseconds = container.nightscoutDouble(.durationInMilliseconds)
        absolute = container.nightscoutDouble(.absolute)
        rate = container.nightscoutDouble(.rate)
        percent = container.nightscoutDouble(.percent)
        isSMB = container.nightscoutBool(.isSMB)
        type = container.nightscoutString(.type)
        automatic = container.nightscoutBool(.automatic)
        reason = container.nightscoutString(.reason)
        notes = container.nightscoutString(.notes)
        isValid = container.nightscoutBool(.isValid)
        enteredBy = container.nightscoutString(.enteredBy)
        app = container.nightscoutString(.app)
        isEmulatingTempBasal = container.nightscoutBool(.isEmulatingTempBasal)
        profile = container.nightscoutString(.profile)
        originalProfileName = container.nightscoutString(.originalProfileName)
        profileJson = container.nightscoutString(.profileJson)
        percentage = container.nightscoutDouble(.percentage)
        timeshift = container.nightscoutDouble(.timeshift)
        if let bolus = try? container.nestedContainer(keyedBy: NestedKeys.self, forKey: .bolus) {
            bolusIsSMB = bolus.nightscoutBool(.isSMB)
        }
        if let rawRate = try? container.nestedContainer(keyedBy: NestedKeys.self, forKey: .rawRate) {
            deliveredUnits = rawRate.nightscoutDouble(.deliveredUnits)
        }
    }

    /// Who uploaded it: `enteredBy`, else API v3's `app`.
    var uploader: String? { enteredBy ?? app }

    /// How the uploader's loop shows in its treatments (the Nightscout coverage's evidence).
    enum LoopFamily: Hashable, Sendable {
        /// oref0 (iAPS, Trio, and any other uploader): a temp at least every 30 min, neutral ones included
        case oref
        /// AAPS (`LoopPlugin.applyTBRRequest`) and Loop cancel the temp at the scheduled rate and set none, so a
        /// quiet stretch at the profile basal has no temp: their temps and pump boluses (SMBs included) are the
        /// evidence, with a wider gap
        case sparse
    }

    var loopFamily: LoopFamily {
        Self.isAAPS(uploader) || (enteredBy?.lowercased().hasPrefix("loop://") ?? false) ? .sparse : .oref
    }

    /// AAPS: API v3's `app` "AAPS", or v1's `enteredBy` "openaps://AndroidAPS" / "AndroidAPS".
    static func isAAPS(_ uploader: String?) -> Bool {
        guard let uploader else { return false }
        return uploader == "AAPS" || uploader.localizedCaseInsensitiveContains("AndroidAPS")
    }

    /// The Nightscout coverage the treatments give, per loop family (`PumpEventStore.nightscoutCoverage`): oref0
    /// uploaders' temp starts with the 3 h gap; AAPS's and Loop's temps and pump boluses with the wider gap. Merged.
    static func coverage(from treatments: [NightscoutInsulinTreatment]) -> [DateInterval] {
        var seen = Set<String>()
        var evidence: [LoopFamily: [Date]] = [:]
        for treatment in treatments where seen.insert(treatment.pagingKey).inserted {
            guard let record = treatment.pumpEvent() else { continue }
            let family = treatment.loopFamily
            switch (record.kind, family) {
            case (.tempBasal, _):
                evidence[family, default: []].append(record.date)
            case (.bolus, .sparse) where !record.isExternal:
                evidence[family, default: []].append(record.date)
            default:
                break
            }
        }
        let intervals = evidence.flatMap { family, dates in
            PumpEventStore.nightscoutCoverage(
                tempStarts: dates,
                gap: family == .oref ? PumpEventStore.Config.nightscoutCoverageGap : PumpEventStore.Config
                    .sparseCoverageGap
            )
        }
        return PumpEventStore.merge(intervals)
    }

    /// What the pager deduplicates by: the document's id. Without one (never from Nightscout), the fields that tell
    /// two treatments apart; never only (eventType, second): a temp basal and its zero-length cancel share both.
    var pagingKey: String {
        if let id = id ?? identifier {
            return id
        }
        let millis = createdAt.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } ?? 0
        return [eventType ?? "", "\(millis)", "\(insulin ?? -1)", "\(duration ?? -1)", "\(absolute ?? rate ?? -1)"]
            .joined(separator: "|")
    }

    /// Profile Switch: the duration in minutes (0: permanent).
    var durationMinutes: Double {
        if let millis = durationInMilliseconds, millis.isFinite {
            return Swift.max(millis / 60000, 0)
        }
        return Swift.max(duration.flatMap { $0.isFinite ? $0 : nil } ?? 0, 0)
    }

    /// The store row this treatment is, or nil (not insulin, unusable, deleted):
    /// - `isValid == false` (AAPS soft deletes): skipped first
    /// - `"SMB"` (iAPS, Trio): an SMB
    /// - `"Bolus"`, `"Correction Bolus"`, `"Meal Bolus"`, `"Snack Bolus"` with `insulin > 0`: a bolus; an SMB with
    ///   `type == "SMB"` (AAPS), `automatic == true` (Loop), `isSMB` or `bolus.isSMB` (iAPS); `type == "PRIMING"`
    ///   (AAPS) skipped
    /// - `"Combo Bolus"` (AAPS extended bolus): a bolus of `enteredinsulin`, unless a `FAKE_EXTENDED` temp carries
    ///   it (`isEmulatingTempBasal`)
    /// - `"External Insulin"`: an external bolus
    /// - `"Temp Basal"`: rate `absolute ?? rate` (AAPS percent temps carry `rate` in U/h), duration
    ///   `durationInMilliseconds` or `duration` (minutes; none: zero-length), units = iAPS's
    ///   `raw_rate.deliveredUnits`, else -1. Only a percent: skipped. A rate-0 temp (Loop suspend, AAPS
    ///   `PUMP_SUSPEND`) is zero basal. No rate, no percent and no duration (AAPS < 3.0's cancel): a zero-length
    ///   temp, which ends the one before.
    /// - `"Note"` "PumpSuspend" / "PumpResume" (Trio): suspend / resume
    func pumpEvent() -> PumpEventRecord? {
        guard isValid != false, let createdAt, let eventType else { return nil }
        let date = createdAt.truncatedToSecond
        let kind = type?.uppercased()

        func bolus(_ units: Double?, smb: Bool = false, external: Bool = false) -> PumpEventRecord? {
            guard let units, units.isFinite, units > 0 else { return nil }
            return PumpEventRecord(
                date: date,
                kind: .bolus,
                source: .nightscout,
                units: units,
                durationMin: 0,
                isSMB: smb,
                isExternal: external
            )
        }

        switch eventType {
        case "SMB":
            return bolus(insulin, smb: true)
        case "Bolus",
             "Correction Bolus",
             "Meal Bolus",
             "Snack Bolus":
            guard kind != "PRIMING" else { return nil }
            let smb = kind == "SMB" || automatic == true || isSMB == true || bolusIsSMB == true
            return bolus(insulin, smb: smb)
        case "Combo Bolus":
            guard isEmulatingTempBasal != true else { return nil }
            return bolus(enteredinsulin ?? insulin)
        case "External Insulin":
            return bolus(insulin, external: true)
        case "Temp Basal":
            let minutes = durationInMilliseconds.map { $0 / 60000 } ?? duration ?? 0
            guard minutes.isFinite else { return nil }
            // AAPS before 3.0 (`NSUpload.uploadTempBasalEnd`) ended a temp with a "Temp Basal" of no rate and no
            // duration: a zero-length temp, which ends the one before. Only a percent, with a duration: skipped.
            let cancel = absolute == nil && self.rate == nil && percent == nil && minutes <= 0
            guard let rate = absolute ?? self.rate ?? (cancel ? 0 : nil), rate.isFinite, rate >= 0 else { return nil }
            return PumpEventRecord(
                date: date,
                kind: .tempBasal,
                source: .nightscout,
                units: deliveredUnits.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? -1,
                rate: rate,
                durationMin: Swift.max(minutes, 0)
            )
        case "Note":
            switch (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
            case "PumpSuspend": return PumpEventRecord(date: date, kind: .suspend, source: .nightscout)
            case "PumpResume": return PumpEventRecord(date: date, kind: .resume, source: .nightscout)
            default: return nil
            }
        default:
            return nil
        }
    }

    // MARK: Pump sessions

    /// A `"Site Change"`'s time, any uploader's and either upload scheme (`PumpSessionRules.activations` clusters
    /// them): iAPS's pod-age copies (one per distinct `podActivatedAt`: Medtrum's phone time and patch clock, seconds
    /// apart) and prime ones (a tube pump's `.prime`), one per change event (iAPS after C3b, Loop: `timestamp` and
    /// `created_at`, `enteredBy` "loop://…", the event's title in `notes`), AAPS's cannula changes (v3: `date`), a
    /// hand-entered one. nil for anything else, or an AAPS soft-deleted one (`isValid == false`).
    var siteChange: Date? {
        guard isValid != false, eventType == "Site Change" else { return nil }
        return createdAt
    }

    /// A pod's or patch's end from iAPS's alarm `"Announcement"` (`NightscoutConversions`: `notes` "Alarm
    /// Optional(\"<title>\") pumpAlarm", the title in the phone's language): MedtrumKit's "Reservoir empty" ran empty,
    /// "Occlusion" and "Patch fault" an occlusion or fault, in any of its languages (`alarmTitles`). Any other
    /// announcement or alarm (a limit, the base restarted, a remote command, the user's) is none: it ends nothing.
    func alarm() -> NightscoutAlarm? {
        guard isValid != false, eventType == "Announcement", let createdAt,
              let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), notes.hasPrefix("Alarm")
        else { return nil }
        guard let reason = Self.alarmTitles.first(where: { notes.contains($0.title) })?.reason else { return nil }
        return NightscoutAlarm(date: createdAt, reason: reason)
    }

    /// MedtrumKit's alert titles that end a patch (`MedtrumAlert.title`), in every language of its string catalog
    /// (`MedtrumKit/Localization/Localizable.xcstrings`), its earlier values too (the catalog's history: an alarm
    /// uploaded within the backfill's 120 days carries the title of its day). None is part of another alert's title
    /// (the limits, the base restarted) in any revision. OmnipodKit uploads no alarms.
    static let alarmTitles: [(title: String, reason: PatchEndReason)] =
        ranEmptyTitles.map { (title: $0, reason: PatchEndReason.ranEmpty) } +
        occlusionOrFaultTitles.map { (title: $0, reason: PatchEndReason.occlusionOrFault) }

    private static let ranEmptyTitles: [String] = [
        "Alert: Reservoir empty",
        "تنبيه: الخزان فارغ",
        "Upozornění: Nádrž je prázdná",
        "Advarsel: Beholderen er tom",
        "Warnung: Reservoir leer",
        "Aviso: Depósito vacío",
        "Hälytys: Säiliö tyhjä",
        "Avertissement : réservoir vide",
        "התראה: מאגר ריק",
        "Figyelem: A tartály üres",
        "Avviso: serbatoio vuoto",
        "警告：貯水タンクが空です",
        "경고: 저수조 비움",
        "Varsel: Tomt reservoar",
        "Waarschuwing: Reservoir leeg",
        "Ostrzeżenie: Zbiornik pusty",
        "Aviso: Reservatório vazio",
        "Avertisment: Rezervorul este gol",
        "Предупреждение: резервуар пуст",
        "Upozornenie: Nádrž je prázdna",
        "Opozorilo: Rezervoar je prazen",
        "Varning: Behållaren är tom",
        "Uyarı: Depo boş",
        "Попередження: резервуар порожній",
        "Cảnh báo: Hồ chứa trống",
        "警报：水箱已空",
        // earlier catalog values (de, nb until September 2026)
        "Warnung: Behälter leer",
        "Varsel: Beholderen er tom"
    ]

    private static let occlusionOrFaultTitles: [String] = [
        "Alert: Occlusion",
        "تنبيه: انسداد",
        "Upozornění: Uzávěr",
        "Advarsel: Blokering",
        "Warnung: Verstopfung",
        "Aviso: Oclusión",
        "Varoitus: Tukos",
        "Avertissement : occlusion",
        "התראה: חסימה",
        "Figyelem: elzáródás",
        "Avviso: occlusione",
        "警告：閉塞",
        "경고: 폐색",
        "Varsel: Blokkering",
        "Waarschuwing: verstopping",
        "Ostrzeżenie: niedrożność",
        "Aviso: Oclusão",
        "Avertisment: Ocluzie",
        "Предупреждение: окклюзия",
        "Upozornenie: Okluzia",
        "Opozorilo: zapora",
        "Varning: Blockering",
        "Uyarı: Tıkanma",
        "Попередження: Оклюзія",
        "Cảnh báo: Tắc nghẽn",
        "警报：阻塞",
        "Alert: Patch fault",
        "تنبيه: خطأ في التصحيح",
        "Upozornění: Chyba v opravě",
        "Advarsel: Fejl i opdateringen",
        "Warnung: Patch-Fehler",
        "Aviso: Error en el parche",
        "Hälytys: Päivitysvirhe",
        "Alerte : erreur de mise à jour",
        "התראה: תקלה בתיקון",
        "Figyelem: Frissítési hiba",
        "Avviso: errore di patch",
        "警告：パッチの不具合",
        "경고: 패치 오류",
        "Varsel: Feil med patch",
        "Waarschuwing: Fout in patch",
        "Ostrzeżenie: Błąd aktualizacji",
        "Aviso: Falha na atualização",
        "Avertisment: Eroare la aplicarea pompei",
        "Предупреждение: Ошибка установки исправления",
        "Upozornenie: Chyba aktualizácie",
        "Opozorilo: Napaka pri namestitvi popravka",
        "Varning: Fel i uppdateringen",
        "Uyarı: Yama hatası",
        "Попередження: Помилка оновлення",
        "Cảnh báo: lỗi vá",
        "警报：贴泵硬件故障",
        // earlier catalog values (de, nb until September 2026; ro until August; zh-Hans until August)
        "Warnung: Okklusion",
        "Warnung: Fehler beim Patch",
        "Varsel: Feil i oppdateringen",
        "Avertisment: Eroare la aplicarea patch-ului",
        "警报：储药器故障",
        "警报：储药贴故障",
        "警报：补丁故障",
        // the first key, "Alert: Occlussion" (12-14 June 2026), in its languages
        "Alert: Occlussion",
        "Upozornění: Okluze",
        "Aviso: oclusión",
        "התראה: סתירה",
        "Advarsel: Blokkering",
        "Waarschuwing: Occlusie",
        "Ostrzeżenie: zablokowanie",
        "Varning: Ocklusion",
        "Cảnh báo: Occlussion"
    ]

    /// The store rows of the fetched treatments (several queries, merged), newest first, one per identity (the
    /// store's `(kind, second)`): a document fetched by two queries counts once (by `pagingKey`); of two temps in
    /// one second the one with a duration wins (a zero-length cancel next to the new temp); otherwise the first.
    static func records(from treatments: [NightscoutInsulinTreatment]) -> [PumpEventRecord] {
        var seenKeys = Set<String>()
        var byIdentity: [PumpEventRecord.Identity: PumpEventRecord] = [:]
        var order: [PumpEventRecord.Identity] = []
        for treatment in treatments where seenKeys.insert(treatment.pagingKey).inserted {
            guard let record = treatment.pumpEvent() else { continue }
            if let existing = byIdentity[record.identity] {
                if record.kind == .tempBasal, existing.durationMin <= 0, record.durationMin > 0 {
                    byIdentity[record.identity] = record
                }
                continue
            }
            byIdentity[record.identity] = record
            order.append(record.identity)
        }
        return order.compactMap { byIdentity[$0] }.sorted { $0.date > $1.date }
    }
}

/// What the insulin backfill stores, prepared from what it fetched (pure; off the main actor).
struct NightscoutInsulinBackfill: Sendable, Equatable {
    let records: [PumpEventRecord]
    let schedules: [NightscoutBasalSchedule]
    /// the pump sessions' input (`PumpEventStore.storeNightscoutSessions`); nil when nothing was fetched completely
    let sessions: NightscoutSessionsInput?

    init(fetched: FetchedInsulin) {
        records = NightscoutInsulinTreatment.records(from: fetched.treatments)
        schedules = NightscoutProfileDocument.basalSchedules(documents: fetched.profiles, switches: fetched.profileSwitches)
        // the sessions' evidence (`NightscoutInsulinTreatment.coverage`)
        sessions = NightscoutSessionsInput(
            fetched: fetched,
            evidence: NightscoutInsulinTreatment.coverage(from: fetched.treatments)
        )
    }
}

/// What the Nightscout pump sessions are built from (`PumpSessionRules.nightscoutSessions`): the Site Changes, the end
/// alarms and the evidence (the insulin treatments' coverage) of the time every insulin and session query fetched
/// completely (`FetchedInsulin.sessionsComplete`).
struct NightscoutSessionsInput: Sendable, Equatable {
    /// both upload schemes, every uploader's (`NightscoutInsulinTreatment.siteChange`), oldest first
    let siteChanges: [Date]
    /// oldest first
    let alarms: [NightscoutAlarm]
    /// `NightscoutInsulinTreatment.coverage`
    let evidence: [DateInterval]
    /// The window's start: the oldest record fetched (a treatment, a Site Change, an alarm Announcement) inside the
    /// complete time. Before it the server returned nothing (pruned history): the sessions stored there stay.
    let from: Date

    init(siteChanges: [Date], alarms: [NightscoutAlarm], evidence: [DateInterval], from: Date) {
        self.siteChanges = siteChanges
        self.alarms = alarms
        self.evidence = evidence
        self.from = from
    }

    /// nil without a complete time or any record in it.
    init?(fetched: FetchedInsulin, evidence: [DateInterval]) {
        guard let complete = fetched.sessionsComplete else { return nil }
        let inside = { (date: Date?) -> Date? in date.flatMap { $0 >= complete.start ? $0 : nil } }
        let lifecycle = fetched.sessionTreatments
        siteChanges = lifecycle.compactMap { inside($0.siteChange) }.sorted()
        alarms = lifecycle.compactMap { treatment in
            treatment.alarm().flatMap { inside($0.date) != nil ? $0 : nil }
        }.sorted { $0.date < $1.date }
        let oldest = (fetched.treatments + lifecycle).compactMap { inside($0.createdAt) }.min()
        guard let oldest else { return nil }
        self.evidence = evidence
        from = oldest
    }
}

// MARK: - Lenient reading

extension KeyedDecodingContainer {
    func nightscoutString(_ key: Key) -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return string
        }
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number.description
        }
        return nil
    }

    /// A number, or a number as a string.
    func nightscoutDouble(_ key: Key) -> Double? {
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number.isFinite ? number : nil
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Double(string.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        }
        return nil
    }

    /// A Bool, "true"/"false", or 0/1.
    func nightscoutBool(_ key: Key) -> Bool? {
        if let bool = try? decodeIfPresent(Bool.self, forKey: key) {
            return bool
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            switch string.lowercased() {
            case "1",
                 "true": return true
            case "0",
                 "false": return false
            default: return nil
            }
        }
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number != 0
        }
        return nil
    }

    /// ISO 8601 text (with or without fractional seconds, of any length, and an offset), or epoch milliseconds.
    func nightscoutDate(_ key: Key) -> Date? {
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return NightscoutDate.parse(string)
        }
        if let millis = try? decodeIfPresent(Double.self, forKey: key) {
            return NightscoutDate.fromMillis(millis)
        }
        return nil
    }
}

enum NightscoutDate {
    /// ISO 8601 with or without fractional seconds (AAPS writes seven digits), or epoch milliseconds as text.
    static func parse(_ string: String) -> Date? {
        let text = string.trimmingCharacters(in: .whitespaces)
        if let date = (try? Date(text, strategy: .iso8601WithFractionalSeconds)) ?? (try? Date(text, strategy: .iso8601)) {
            return date
        }
        // a fraction of another length: parsed without it, added back
        if let dot = text.firstIndex(of: "."), text[text.index(after: dot)...].first?.isNumber == true {
            let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
            let rest = text[text.index(after: dot)...].dropFirst(digits.count)
            let whole = String(text[..<dot]) + rest
            if let date = try? Date(whole, strategy: .iso8601), let fraction = Double("0." + digits) {
                return date.addingTimeInterval(fraction)
            }
        }
        return Double(text).flatMap(fromMillis)
    }

    /// Epoch milliseconds, within 1970 ... 9999 (beyond it a date's millisecond arithmetic overflows).
    static func fromMillis(_ millis: Double) -> Date? {
        guard millis.isFinite, millis > 0, millis < 253_402_300_800_000 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}
