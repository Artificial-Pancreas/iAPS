import Foundation
import NightscoutKit
import Swinject

protocol NightscoutManager: Sendable {
    func isConfigured() async -> Bool
    func fetchGlucose(since date: Date) async -> AsyncStream<FetchGlucoseProgress>
    func fetchCarbs() async -> [CarbsEntry]
    func fetchTempTargets() async -> [TempTarget]
    func fetchAnnouncements() async -> [Announcement]
    func uploadOldGlucose(bloodGlucose: [BloodGlucose]) async -> AsyncStream<Double>
    func uploadProfileAndSettings(profile: NightscoutProfileStore?, force: Bool) async
    func uploadOverride(_ profile: String, _ duration: Double, _ date: Date) async
    func deleteOverride(at date: Date) async
    func deleteAnnouncements() async
    func deleteAllNSoverrrides() async
    func fetchProfile() async throws -> [FetchedNightscoutProfileStore]
    /// The insulin backfill: the insulin treatments and the basal schedules since `date`. Read-only GETs, on demand.
    func fetchInsulin(since date: Date) async -> AsyncStream<FetchInsulinProgress>
}

enum FetchInsulinProgress: Sendable {
    /// the fraction of the time span the slowest query fetched
    case progress(Double)
    case done(FetchedInsulin)
}

/// What the insulin backfill fetched.
struct FetchedInsulin: Sendable {
    /// the insulin treatments of every query, merged (`NightscoutInsulinTreatment.records(from:)` maps them)
    var treatments: [NightscoutInsulinTreatment] = []
    /// the time every insulin query fetched completely: from `since` (or, after a failed page, from the newest point
    /// any query stopped at) to the fetch's end. Nothing outside it is stored, nor covered.
    var complete: DateInterval?
    /// the profile documents of the range, plus the one in effect when it starts
    var profiles: [NightscoutProfileDocument] = []
    /// AAPS's "Profile Switch" treatments of the range, plus the one in effect when it starts
    var profileSwitches: [NightscoutInsulinTreatment] = []
    var failure: FetchGlucoseFailure?
    /// why the basal schedules couldn't be fetched (the insulin treatments are kept)
    var schedulesFailure: String?
    /// the Site Changes and Announcements (`NightscoutInsulinQuery.sessions`), from `sessionsComplete` on
    var sessionTreatments: [NightscoutInsulinTreatment] = []
    /// the time every insulin and session query fetched completely (within `complete`): the Nightscout pump sessions
    /// are built there only, a session query's failure shortening it, never the insulin records' time
    var sessionsComplete: DateInterval?
    /// why a session query stopped early (the insulin treatments are kept)
    var sessionsFailure: String?
}

/// The GETs of the insulin backfill (`NightscoutAPI` in the app; the tests fake the server).
struct InsulinBackfillSource: Sendable {
    /// one page of a query's treatments in the interval (both ends included), newest first
    let treatments: @Sendable(NightscoutInsulinQuery, DateInterval) async throws -> [NightscoutInsulinTreatment]
    /// the newest treatments of the query before the date, at most `count`, newest first
    let treatmentsBefore: @Sendable(NightscoutInsulinQuery, Date, Int) async throws -> [NightscoutInsulinTreatment]
    /// one page of profile documents with `startDate` in the interval, newest first
    let profiles: @Sendable(DateInterval) async throws -> [NightscoutProfileDocument]
    /// the newest profile document before the date
    let profileBefore: @Sendable(Date) async throws -> NightscoutProfileDocument?
}

/// The paged entries of one query, newest first.
struct FetchedTreatmentPages<Entry: Sendable>: Sendable {
    var entries: [Entry] = []
    /// the oldest entry fetched
    var oldest: Date?
    /// why paging stopped early; nil: it reached `since`, or the entries ran out
    var error: (any Error)?

    /// From when on the query's entries are all fetched: `since` when it finished, else the second after the oldest
    /// entry (a page cut inside a second can leave out others of it), or the fetch's end when it got nothing.
    func complete(since: Date, until: Date) -> Date {
        guard error != nil else { return since }
        guard let oldest else { return until }
        return Swift.min(oldest.truncatedToSecond.addingTimeInterval(1), until)
    }
}

enum FetchGlucoseProgress: Sendable {
    /// the fraction of the time span fetched
    case progress(Double)
    case done(FetchedGlucose)
}

/// The readings a backfill fetched, newest first, and why it stopped early (nil: it got the whole span).
struct FetchedGlucose: Sendable {
    let glucose: [BloodGlucose]
    let failure: FetchGlucoseFailure?
}

enum FetchGlucoseFailure: Sendable, Equatable {
    case notConfigured
    case notReachable
    /// a page failed: the readings fetched go back to `reached` (nil: none were)
    case pageFailed(reached: Date?, error: String)
}

enum FetchPagesError: LocalizedError {
    /// a page with newer entries, not older ones than the page before
    case notPagingBack

    var errorDescription: String? {
        switch self {
        case .notPagingBack:
            return NSLocalizedString("Nightscout ignored the requested date range", comment: "Glucose backfill error")
        }
    }
}

actor BaseNightscoutManager: NightscoutManager {
    private let apiProvider: NightscoutAPIProvider
    private let appCoordinator: AppCoordinator
    private let tempTargetsStorage: TempTargetsStorage
    private let carbsStorage: CarbsStorage
    private let storage: FileStorage
    private let announcementsStorage: AnnouncementsStorage
    private let reachabilityManager: ReachabilityManager
    private let overridesUploader: NightscoutOverridesUploader

    private let overrideStorage: OverrideStorage

    private var ping: TimeInterval?

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private var nightscoutAPI: NightscoutAPI? {
        apiProvider.api
    }

    init(
        apiProvider: NightscoutAPIProvider,
        appCoordinator: AppCoordinator,
        tempTargetsStorage: TempTargetsStorage,
        carbsStorage: CarbsStorage,
        storage: FileStorage,
        announcementsStorage: AnnouncementsStorage,
        reachabilityManager: ReachabilityManager,
        overridesUploader: NightscoutOverridesUploader,
        overrideStorage: OverrideStorage
    ) {
        self.apiProvider = apiProvider
        self.appCoordinator = appCoordinator
        self.tempTargetsStorage = tempTargetsStorage
        self.carbsStorage = carbsStorage
        self.storage = storage
        self.announcementsStorage = announcementsStorage
        self.reachabilityManager = reachabilityManager
        self.overridesUploader = overridesUploader
        self.overrideStorage = overrideStorage
    }

    func isConfigured() async -> Bool {
        nightscoutAPI != nil
    }

    func sourceInfo() -> [String: Any]? {
        if let ping = ping {
            return [GlucoseSourceKey.nightscoutPing.rawValue: ping]
        }
        return nil
    }

    func fetchGlucose(since sinceDate: Date) async -> AsyncStream<FetchGlucoseProgress> {
        AsyncStream { continuation in
            Task {
                ping = nil

                guard let nightscout = nightscoutAPI else {
                    continuation.yield(.done(FetchedGlucose(glucose: [], failure: .notConfigured)))
                    continuation.finish()
                    return
                }
                guard isNetworkReachable else {
                    continuation.yield(.done(FetchedGlucose(glucose: [], failure: .notReachable)))
                    continuation.finish()
                    return
                }

                let startDate = Date()
                let secondsToFetch = startDate.timeIntervalSince(sinceDate)

                let pages = await Self.fetchPages(
                    since: sinceDate,
                    until: startDate.addingTimeInterval(10 * 60),
                    date: { (entry: GlucoseEntry) in entry.date },
                    page: { interval in
                        debug(
                            .nightscout,
                            "requesting glucose records page from nightscout: \(interval.start) .. \(interval.end)"
                        )
                        return try await nightscout.fetchGlucose(dateInterval: interval)
                    },
                    reached: { oldest in
                        if secondsToFetch > 0 {
                            continuation.yield(.progress((startDate.timeIntervalSince(oldest) / secondsToFetch).clamped()))
                        }
                    }
                )
                let glucose = pages.entries.compactMap { BloodGlucose.from(nightscout: $0) }

                if glucose.isNotEmpty {
                    ping = Date().timeIntervalSince(startDate)
                }

                let failure = pages.error
                    .map { FetchGlucoseFailure.pageFailed(reached: pages.oldest, error: $0.localizedDescription) }
                continuation.yield(.progress(1))
                continuation.yield(.done(FetchedGlucose(glucose: glucose, failure: failure)))
                continuation.finish()
            }
        }
    }

    /// Pages back through the entries newer than `since`, from `until`, newest page first. A page is the newest
    /// entries up to its end (the API caps how many); the next one ends just before the oldest of them. Nightscout
    /// compares the end as a whole-second string, so a page can repeat the entries of the boundary second: only the
    /// ones older than the page before are taken. An empty page, one reaching `since`, or one with only those
    /// repeated entries is the last. A failed page ends it too, and so does a page with newer entries that does not
    /// go back (a server ignoring the end): `error` says why, and `entries` are the ones before it, back to `oldest`
    /// (the oldest entry fetched). `reached`: the oldest entry of each page that has a next one.
    static func fetchPages<Entry: Sendable>(
        since: Date,
        until: Date,
        date: @Sendable(Entry) -> Date,
        page: @Sendable(DateInterval) async throws -> [Entry],
        reached: @Sendable(Date) -> Void
    ) async -> (entries: [Entry], oldest: Date?, error: (any Error)?) {
        var entries: [Entry] = []
        var oldestFetched: Date?
        var end = until
        while true {
            let chunk: [Entry]
            do {
                chunk = try await page(DateInterval(start: since, end: end))
            } catch {
                return (entries, oldestFetched, error)
            }
            guard let oldest = chunk.map(date).min() else { break }
            if let previous = oldestFetched, oldest >= previous {
                // nothing older: the boundary second again (the last page), or a server not paging back
                let boundary = end.addingTimeInterval(1)
                if chunk.allSatisfy({ boundary >= date($0) }) { break }
                return (entries, oldestFetched, FetchPagesError.notPagingBack)
            }
            entries += chunk.filter { entry in
                date(entry) > since && (oldestFetched.map { $0 > date(entry) } ?? true)
            }
            oldestFetched = oldest
            // the fetch includes its end, so the next page ends a millisecond before the oldest entry
            let next = oldest.addingTimeInterval(-0.001)
            guard next > since else { break }
            reached(oldest)
            end = next
        }
        return (entries, oldestFetched, nil)
    }

    /// The sibling of `fetchPages` for treatments, one query at a time: treatments often share a second (an SMB and a
    /// temp basal enacted together), and a page cut inside a second would lose the ones the page didn't get. So each
    /// page ends at (or after) the previous page's oldest entry, both ends included, and the entries are
    /// deduplicated by `key` against those fetched already. The end is the second after that entry: Nightscout
    /// normalizes `created_at` to ISO UTC with milliseconds (v1 `prepareData`, the v3 fallback), so the oldest
    /// entry's own time would do; the second after is a harmless superset that also covers a document stored without
    /// that normalization. Paging stops on a page that adds nothing new (the boundary second again, or nothing), on
    /// reaching `since`, or on a failed page (`error`; the entries so far are kept). With `checksEnd`, a page with
    /// entries newer than its end (a server ignoring it) is `FetchPagesError.notPagingBack`; profile documents skip
    /// that check, since their `startDate` is compared as stored (a string with an offset can sort apart from its
    /// time). Entries without a date are dropped. `reached`: the oldest entry of each page that has a next one.
    static func fetchTreatmentPages<Entry: Sendable, Key: Hashable>(
        since: Date,
        until: Date,
        checksEnd: Bool = true,
        date: @Sendable(Entry) -> Date?,
        key: @Sendable(Entry) -> Key,
        page: @Sendable(DateInterval) async throws -> [Entry],
        reached: @Sendable(Date) -> Void
    ) async -> FetchedTreatmentPages<Entry> {
        var result = FetchedTreatmentPages<Entry>()
        var seen = Set<Key>()
        var end = until
        while end >= since {
            let chunk: [Entry]
            do {
                chunk = try await page(DateInterval(start: since, end: end))
            } catch {
                result.error = error
                return result
            }
            var added = 0
            var pageOldest: Date?
            var newerThanEnd = false
            for entry in chunk {
                guard let entryDate = date(entry) else { continue }
                if entryDate > end.addingTimeInterval(1) {
                    newerThanEnd = true
                }
                pageOldest = Swift.min(pageOldest ?? entryDate, entryDate)
                guard entryDate >= since, seen.insert(key(entry)).inserted else { continue }
                result.entries.append(entry)
                added += 1
            }
            guard added > 0, let oldest = pageOldest else {
                if checksEnd, newerThanEnd {
                    result.error = FetchPagesError.notPagingBack
                }
                break
            }
            result.oldest = Swift.min(result.oldest ?? oldest, oldest)
            guard oldest > since else { break }
            reached(oldest)
            end = oldest.truncatedToSecond.addingTimeInterval(1)
        }
        return result
    }

    func fetchInsulin(since sinceDate: Date) async -> AsyncStream<FetchInsulinProgress> {
        AsyncStream { continuation in
            Task {
                guard let nightscout = nightscoutAPI else {
                    continuation.yield(.done(FetchedInsulin(failure: .notConfigured)))
                    continuation.finish()
                    return
                }
                guard isNetworkReachable else {
                    continuation.yield(.done(FetchedInsulin(failure: .notReachable)))
                    continuation.finish()
                    return
                }
                let fetched = await Self.fetchInsulin(
                    since: sinceDate,
                    until: Date().addingTimeInterval(10 * 60),
                    source: InsulinBackfillSource(
                        treatments: { query, interval in
                            debug(.nightscout, "insulin backfill: \(query) page \(interval.start) .. \(interval.end)")
                            return try await nightscout.fetchInsulinTreatments(query, dateInterval: interval)
                        },
                        treatmentsBefore: { try await nightscout.fetchInsulinTreatments($0, before: $1, count: $2) },
                        profiles: { interval in
                            debug(.nightscout, "insulin backfill: profiles page \(interval.start) .. \(interval.end)")
                            return try await nightscout.fetchProfileDocuments(dateInterval: interval)
                        },
                        profileBefore: { try await nightscout.fetchProfileDocument(before: $0) }
                    ),
                    progress: { continuation.yield(.progress($0)) }
                )
                continuation.yield(.done(fetched))
                continuation.finish()
            }
        }
    }

    /// Every insulin query with its own pager, at once (a pager over merged results would end each page at the oldest
    /// entry of either query, and skip the other's entries between the two). A failed query stops the treatments at
    /// the newest point any query stopped at: the treatments are kept from there on only, so what is stored, and the
    /// coverage built from it, is complete. The profile documents and the profile switches come along; their failure
    /// skips only the schedules. So do the pump sessions' Site Changes and Announcements: their failure shortens only
    /// the sessions' time (`sessionsComplete`). `progress`: the share of the span the slowest query fetched.
    /// the profile switches fetched from before the range
    static let switchesBefore = 10

    static func fetchInsulin(
        since: Date,
        until: Date,
        source: InsulinBackfillSource,
        progress: @escaping @Sendable(Double) -> Void
    ) async -> FetchedInsulin {
        let queries = NightscoutInsulinQuery.insulin + NightscoutInsulinQuery.sessions + [.profileSwitches]
        let tracker = ProgressTracker(queries: queries.count + 1, since: since, until: until, report: progress)

        async let profiles = fetchProfileHistory(since: since, until: until, source: source) { oldest in
            Task { await tracker.reached(oldest, by: queries.count) }
        }
        let pages = await withTaskGroup(of: (Int, FetchedTreatmentPages<NightscoutInsulinTreatment>).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    let result = await fetchTreatmentPages(
                        since: since,
                        until: until,
                        date: { $0.createdAt },
                        key: { $0.pagingKey },
                        page: { try await source.treatments(query, $0) },
                        reached: { oldest in Task { await tracker.reached(oldest, by: index) } }
                    )
                    await tracker.finished(index)
                    return (index, result)
                }
            }
            var pages = [Int: FetchedTreatmentPages<NightscoutInsulinTreatment>]()
            for await (index, result) in group {
                pages[index] = result
            }
            return pages
        }

        var fetched = FetchedInsulin()
        let insulin = NightscoutInsulinQuery.insulin.indices.compactMap { pages[$0] }
        // the newest point a query stopped at: every query is complete from there on
        let complete = insulin.map { $0.complete(since: since, until: until) }.max() ?? since
        fetched.complete = DateInterval(start: complete, end: Swift.max(complete, until))
        fetched.treatments = insulin.flatMap(\.entries).filter { ($0.createdAt ?? .distantPast) >= complete }
        if let failed = insulin.first(where: { $0.error != nil }), let error = failed.error {
            fetched.failure = .pageFailed(
                // nil: nothing is complete (then nothing is kept)
                reached: complete < until ? complete : nil,
                error: error.localizedDescription
            )
        }

        // the pump sessions' Site Changes and alarms: complete where the insulin (their evidence) is too
        let lifecycle = NightscoutInsulinQuery.sessions.indices.compactMap { pages[NightscoutInsulinQuery.insulin.count + $0] }
        let sessionsComplete = ([complete] + lifecycle.map { $0.complete(since: since, until: until) }).max() ?? complete
        fetched.sessionsComplete = DateInterval(start: sessionsComplete, end: Swift.max(sessionsComplete, until))
        fetched.sessionTreatments = lifecycle.flatMap(\.entries).filter { ($0.createdAt ?? .distantPast) >= sessionsComplete }
        fetched.sessionsFailure = lifecycle.compactMap(\.error).first?.localizedDescription

        // the schedules: the profile switch in effect when the range starts, the switches, the documents
        let switches = pages[queries.count - 1] ?? FetchedTreatmentPages()
        do {
            if let error = switches.error {
                throw error
            }
            // the switches before the range, back to a permanent one when it is among them: a temporary switch needs
            // the one it ends into. The newest few, not only one: the one before is often temporary, or deleted
            // (`isValid == false`: Nightscout's v1 query can't filter a Bool, the walker leaves "false" a string)
            let before = try await source.treatmentsBefore(.profileSwitches, since, Self.switchesBefore)
                .filter { $0.isValid != false }
            fetched.profileSwitches = switches.entries + before
            fetched.profiles = try await profiles
        } catch {
            fetched.schedulesFailure = error.localizedDescription
            fetched.profileSwitches = []
            fetched.profiles = []
        }
        // the fetch is done: 1, and no late report after it
        await tracker.finish()
        return fetched
    }

    /// The profile documents dated in the range (paged like the treatments, deduplicated by `_id`), plus the newest
    /// one before it: the schedule in effect when the range starts.
    private static func fetchProfileHistory(
        since: Date,
        until: Date,
        source: InsulinBackfillSource,
        reached: @escaping @Sendable(Date) -> Void
    ) async throws -> [NightscoutProfileDocument] {
        let pages = await fetchTreatmentPages(
            since: since,
            until: until,
            checksEnd: false,
            date: { $0.startDate },
            key: { $0.pagingKey },
            page: { try await source.profiles($0) },
            reached: reached
        )
        // done: as far as the progress goes
        reached(since)
        if let error = pages.error {
            throw error
        }
        let before = try await source.profileBefore(since)
        return pages.entries + (before.map { [$0] } ?? [])
    }

    /// The progress of queries running at once: the share of `[since, until]` the slowest one reached.
    private actor ProgressTracker {
        /// the oldest entry each query reached
        private var positions: [Date]
        /// the highest fraction reported: progress never goes back
        private var reported = 0.0
        private var done = false
        private let since: Date
        private let until: Date
        private let report: @Sendable(Double) -> Void

        init(queries: Int, since: Date, until: Date, report: @escaping @Sendable(Double) -> Void) {
            positions = Array(repeating: until, count: queries)
            self.since = since
            self.until = until
            self.report = report
        }

        func reached(_ date: Date, by query: Int) {
            guard positions.indices.contains(query) else { return }
            positions[query] = Swift.min(positions[query], date)
            reportSlowest()
        }

        /// the query is done (it reached `since`, ran out, or failed)
        func finished(_ query: Int) {
            reached(since, by: query)
        }

        /// every query is done: 1, and nothing after it (a `reached` still in flight)
        func finish() {
            guard !done else { return }
            done = true
            report(1)
        }

        private func reportSlowest() {
            let span = until.timeIntervalSince(since)
            guard !done, span > 0, let slowest = positions.max() else { return }
            let fraction = (until.timeIntervalSince(slowest) / span).clamped()
            guard fraction > reported else { return }
            reported = fraction
            report(fraction)
        }
    }

    func fetchCarbs() async -> [CarbsEntry] {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return []
        }

        let since = await carbsStorage.syncDate()
        return await nightscout.fetchCarbs(sinceDate: since)
    }

    func fetchTempTargets() async -> [TempTarget] {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return []
        }

        let since = await tempTargetsStorage.syncDate()
        return await nightscout.fetchTempTargets(sinceDate: since)
    }

    func fetchAnnouncements() async -> [Announcement] {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return []
        }
        let since = await announcementsStorage.syncDate()
        return await nightscout.fetchAnnouncement(sinceDate: since)
    }

    func deleteAnnouncements() async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }
        do {
            try await nightscout.deleteAnnouncements()
            debug(.nightscout, "Annuncement(s) deleted from NS.")
        } catch {
            info(
                .nightscout,
                "Deletion of Announcements not possible \(error.localizedDescription)",
                type: MessageType.warning
            )
        }
    }

    func uploadProfileAndSettings(profile: NightscoutProfileStore?, force: Bool) async {
        let settings = appCoordinator.settings.value
        guard settings.isUploadEnabled,
              !NightscoutUploadPause.isPaused,
              let profile,
              let ps = profile.store[profile.defaultProfile],
              let ns = nightscoutAPI
        else { return }

        let uploadedProfile = await storage.retrieve(OpenAPS.Nightscout.uploadedProfile, as: NightscoutProfileStore.self)
        // UPLOAD Profiles WHEN CHANGED
        if uploadedProfile?.store["default"] != ps || force {
            do {
                try await ns.uploadProfile(profile)
                await storage.save(profile, as: OpenAPS.Nightscout.uploadedProfile)
                debug(.nightscout, "Profile uploaded")
            } catch {
                debug(.nightscout, error.localizedDescription)
            }
        } else {
            debug(.nightscout, "uploadProfile, no profile change")
        }
    }

    func uploadOldGlucose(bloodGlucose glucose: [BloodGlucose]) async -> AsyncStream<Double> {
        AsyncStream { continuation in
            Task {
                let settings = appCoordinator.settings.value
                guard settings.isUploadEnabled, !glucose.isEmpty, let nightscout = nightscoutAPI,
                      appCoordinator.cgmStatus.value?.shouldUploadGlucose == true
                else {
                    continuation.finish()
                    return
                }

                // check if unique code
                // var uuid = UUID(uuidString: yourString) This will return nil if yourString is not a valid UUID
                let glucoseWithCorrectID = glucose.filter { UUID(uuidString: $0._id) != nil }
                let total = glucoseWithCorrectID.count
                var uploaded = 0
                continuation.yield(0.0)

                do {
                    for chunk in glucoseWithCorrectID.chunks(ofCount: 100) {
                        let entries = chunk.compactMap(\.toNightscoutEntry)
                        _ = try await nightscout.uploadGlucose(Array(entries))
                        uploaded += chunk.count
                        if total != 0 {
                            continuation.yield(Double(uploaded) / Double(total))
                        } else {
                            continuation.yield(1.0)
                        }
                    }
                    debug(.nightscout, "Glucose uploaded")

                } catch {
                    debug(.nightscout, "Upload of glucose failed: " + error.localizedDescription)
                }

                continuation.finish()
            }
        }
    }

    func uploadOverride(_ profile: String, _ duration: Double, _ date: Date) async {
        await overridesUploader.uploadOverride(profile, duration, date)
    }

    func deleteOverride(at date: Date) async {
        await overridesUploader.deleteOverride(at: date)
    }

    func deleteAllNSoverrrides() async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }
        do {
            try await nightscout.deleteAllNSoverrrides()
            debug(.nightscout, "All Overrides deleted in NS")
        } catch {
            debug(.nightscout, "Deletion of all overrides in NS failed: " + error.localizedDescription)
        }
    }

    func fetchProfile() async throws -> [FetchedNightscoutProfileStore] {
        guard let nightscout = nightscoutAPI else {
            return []
        }
        return try await nightscout.fetchProfile()
    }
}

private extension AsyncSequence {
    func drain() async rethrows {
        for try await _ in self {}
    }
}
