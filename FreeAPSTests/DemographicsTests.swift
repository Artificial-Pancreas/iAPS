@testable import FreeAPS
import XCTest

/// Settings › Demographics and the share toggles of Settings › Sharing (`DemographicsSharing`): the one-time migration
/// at the start (`DataMigrations`), a value cleared turning its toggle off, the birth date read as a day, what the
/// daily Statistics upload carries, the Daily Log gate, the age, the birth date across time zones, the Reference
/// intakes sheet's Save and the height in feet and inches.
final class DemographicsTests: XCTestCase {
    private static let berlin = TimeZone(identifier: "Europe/Berlin")!

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar
    }()

    private var calendar: Calendar { Self.calendar }

    /// 2026-11-02 12:00 Europe/Berlin
    private let now = Date(timeIntervalSince1970: 1_793_617_200)

    /// a birth date as kept: the day at 12:00 UTC
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DemographicsSharing.birthCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func zone(_ hours: Int) -> TimeZone {
        TimeZone(secondsFromGMT: hours * 3600)!
    }

    /// midnight of a day in `timeZone`: what the old date picker kept
    private func midnight(_ year: Int, _ month: Int, _ day: Int, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func settings(
        sex: Int = 3,
        birthDate: Date = .distantPast,
        weight: Decimal = 0,
        height: Decimal = 0,
        uploadStats: Bool = false
    ) -> FreeAPSSettings {
        var settings = FreeAPSSettings()
        settings.sexSetting = sex
        settings.birthDate = birthDate
        settings.weight = weight
        settings.height = height
        settings.uploadStats = uploadStats
        return settings
    }

    // MARK: - Migration

    /// Each value set before the toggles stays shared, whatever Online Backup is; one not set is not shared.
    func testMigrationSharesWhatWasSet() {
        for uploadStats in [false, true] {
            for sex in 0 ... 2 {
                let migrated = settings(sex: sex, uploadStats: uploadStats).migratingDemographicsSharing()
                XCTAssertTrue(migrated.shareSex, "sex \(sex)")
                XCTAssertFalse(migrated.shareAge)
                XCTAssertTrue(migrated.demographicsSharingMigrated)
            }
            let notSet = settings(uploadStats: uploadStats).migratingDemographicsSharing()
            XCTAssertFalse(notSet.shareSex)
            XCTAssertFalse(notSet.shareAge)
            XCTAssertTrue(notSet.demographicsSharingMigrated)

            // the old picker's midnight in Berlin, the phone there
            let born = settings(birthDate: midnight(1985, 3, 14, in: Self.berlin), uploadStats: uploadStats)
                .migratingDemographicsSharing(timeZone: Self.berlin)
            XCTAssertTrue(born.shareAge)
            XCTAssertFalse(born.shareSex)
            // the full birth date stays on the phone, as its day
            XCTAssertEqual(born.birthDate, day(1985, 3, 14))

            // the weight and the height aren't shared (the settings backup carries them)
            let body = settings(weight: 68, height: 172, uploadStats: uploadStats).migratingDemographicsSharing()
            XCTAssertFalse(body.shareSex)
            XCTAssertFalse(body.shareAge)
            XCTAssertEqual(body.weight, 68)
        }
    }

    /// A settings file from before the toggles decodes as not migrated (the migration looks for the key itself); one
    /// written since has the key, with a fresh install's settings too (false: never migrated).
    func testMigrationFlagDecoding() throws {
        let old = try FreeAPSSettings.decodeFrom(json: #"{"sexSetting": 1, "weight": 80}"#)
        XCTAssertFalse(old.demographicsSharingMigrated)
        let migrated = old.migratingDemographicsSharing()
        XCTAssertTrue(migrated.shareSex)
        XCTAssertFalse(migrated.shareAge)

        let written = try FreeAPSSettings.decodeFrom(json: migrated.rawJSON)
        XCTAssertTrue(written.demographicsSharingMigrated)
        XCTAssertTrue(written.shareSex)
        XCTAssertNotNil(FreeAPSSettings().dictionaryRepresentation?["demographicsSharingMigrated"])
    }

    // MARK: - The migration at the start (DataMigrations)

    private func migrate(_ files: IsolatedFileStorage, timeZone: TimeZone = DemographicsTests.berlin) async {
        await DataMigrations.migrateDemographicsSharing(storage: files, timeZone: timeZone)
    }

    /// `settings` in a file as an older build wrote it: without the `demographicsSharingMigrated` key, nor the toggles
    private func saveOlderFile(_ settings: FreeAPSSettings, to files: IsolatedFileStorage) async throws {
        var object = try XCTUnwrap(settings.dictionaryRepresentation)
        for key in ["demographicsSharingMigrated", "shareSex", "shareAge"] {
            object.removeValue(forKey: key)
        }
        let raw = try XCTUnwrap(object.rawJSON)
        try await files.save(raw: raw, as: OpenAPS.FreeAPS.settings, decodingInto: FreeAPSSettings.self)
    }

    private func stored(_ files: IsolatedFileStorage) async throws -> FreeAPSSettings {
        let settings = await files.retrieve(OpenAPS.FreeAPS.settings, as: FreeAPSSettings.self)
        return try XCTUnwrap(settings)
    }

    /// A file without the key: each value set stays shared, a legacy birth date becomes its day (the phone's zone
    /// passed), and the key is written.
    func testStartMigratesAFileWithoutTheKey() async throws {
        let auckland = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        // (sex, birth date in the file, the phone's zone, sex shared, age shared, the birth date migrated)
        let cases: [(Int, Date, TimeZone, Bool, Bool, Date)] = [
            (0, .distantPast, Self.berlin, true, false, .distantPast),
            (1, .distantPast, Self.berlin, true, false, .distantPast),
            (2, .distantPast, Self.berlin, true, false, .distantPast),
            (3, .distantPast, Self.berlin, false, false, .distantPast),
            // the old picker's midnight, the phone where it was entered or elsewhere (`legacyBirthDay`)
            (3, midnight(1985, 3, 14, in: Self.berlin), Self.berlin, false, true, day(1985, 3, 14)),
            (1, midnight(1985, 3, 14, in: Self.berlin), newYork, true, true, day(1985, 3, 14)),
            (0, midnight(1985, 7, 14, in: newYork), Self.berlin, true, true, day(1985, 7, 14)),
            (1, midnight(1985, 7, 14, in: auckland), auckland, true, true, day(1985, 7, 14)),
            (1, midnight(1990, 1, 1, in: zone(1)), zone(-5), true, true, day(1990, 1, 1)),
            // a day this build kept, the key dropped by a downgrade: kept
            (2, day(1990, 1, 1), Self.berlin, true, true, day(1990, 1, 1))
        ]
        for (sex, birthDate, phone, shareSex, shareAge, migratedBirthDate) in cases {
            let label = "sex \(sex), born \(birthDate), \(phone.identifier)"
            let files = IsolatedFileStorage()
            try await saveOlderFile(settings(sex: sex, birthDate: birthDate), to: files)
            await migrate(files, timeZone: phone)
            let migrated = try await stored(files)
            XCTAssertEqual(migrated.shareSex, shareSex, label)
            XCTAssertEqual(migrated.shareAge, shareAge, label)
            XCTAssertEqual(migrated.birthDate, migratedBirthDate, label)
            XCTAssertEqual(migrated.sexSetting, sex, label)
            XCTAssertTrue(migrated.demographicsSharingMigrated, label)
            let raw = await files.retrieveRaw(OpenAPS.FreeAPS.settings)
            XCTAssertTrue(raw?.contains(#""demographicsSharingMigrated" : true"#) == true, label)
        }
    }

    /// Every other setting is as it was: the file decoded before and after differs only in the demographics.
    func testStartMigrationKeepsEveryOtherSetting() async throws {
        let files = IsolatedFileStorage()
        var file = settings(sex: 1, birthDate: midnight(1985, 3, 14, in: Self.berlin), weight: 81.5, height: 178)
        file.uploadStats = true
        file.weightInLb = true
        file.useInsulinBars = true
        file.profileID = "Exercise"
        try await saveOlderFile(file, to: files)
        let before = try await stored(files)

        await migrate(files)
        let after = try await stored(files)
        XCTAssertNotEqual(after, before)
        var expected = before
        expected.shareSex = after.shareSex
        expected.shareAge = after.shareAge
        expected.birthDate = after.birthDate
        expected.demographicsSharingMigrated = after.demographicsSharingMigrated
        XCTAssertEqual(after, expected)
        XCTAssertEqual(after.birthDate, day(1985, 3, 14))
        XCTAssertTrue(after.shareSex)
        XCTAssertTrue(after.shareAge)
    }

    /// An older build's file, as its encoder wrote it: the dosing Decimals as their digits, a Double as its 17 digits,
    /// Bools, nested objects, and keys this build doesn't know (another branch's), with an array and nulls.
    private static let olderSettingsFile = """
    {
      "units" : "mg/dL",
      "closedLoop" : true,
      "useInsulinBars" : false,
      "insulinReqPercentage" : 70.5,
      "autoisf_max" : 1.35,
      "smbDeliveryRatioMin" : 0.65,
      "minimumSMB" : 0.15,
      "bgBrakeISFweight" : 0.1,
      "individualAdjustmentFactor" : 0.7,
      "sensorDays" : 3.3,
      "weight" : 81.299999999999997,
      "height" : 178,
      "timeCap" : 8,
      "sexSetting" : 1,
      "birthDate" : "1985-03-13T23:00:00.000Z",
      "glucoseSmoothing" : {
        "algorithm" : "kalman",
        "kalman" : {
          "responsiveness" : "calm"
        }
      },
      "aKeyThisBuildDoesNotKnow" : {
        "nested" : true,
        "value" : 1.5,
        "values" : [
          0.1,
          3.3,
          null,
          "x",
          {
            "deep" : 0.7
          },
          []
        ],
        "none" : null,
        "count" : 1793617200,
        "negative" : -0.25
      },
      "anotherUnknownKey" : null
    }
    """

    /// The file itself: only the demographics keys are added or changed (the legacy birth date becomes its day, the
    /// toggles and the key added); every other value, the keys this build doesn't know included, keeps its text (the
    /// numbers compared as written, not as Doubles: 0.1 stays 0.1, the Double's 17 digits stay those).
    func testStartMigrationKeepsTheFileAsItWas() async throws {
        let files = IsolatedFileStorage()
        try await files.save(
            raw: Self.olderSettingsFile,
            as: OpenAPS.FreeAPS.settings,
            decodingInto: FreeAPSSettings.self
        )
        let before = try JSONLiterals.of(Self.olderSettingsFile)

        await migrate(files)
        let storedAfter = await files.retrieveRaw(OpenAPS.FreeAPS.settings)
        let after = try JSONLiterals.of(XCTUnwrap(storedAfter))
        let demographics: Set = ["shareSex", "shareAge", "birthDate", "demographicsSharingMigrated"]
        for (path, literal) in before where !demographics.contains(path) {
            XCTAssertEqual(after[path], literal, path)
        }
        XCTAssertEqual(Set(after.keys).subtracting(before.keys), ["shareSex", "shareAge", "demographicsSharingMigrated"])
        XCTAssertTrue(Set(before.keys).isSubset(of: after.keys))
        XCTAssertEqual(after["birthDate"], #""1985-03-14T12:00:00.000Z""#)
        XCTAssertEqual(after["shareSex"], "true")
        XCTAssertEqual(after["shareAge"], "true")
        XCTAssertEqual(after["demographicsSharingMigrated"], "true")
        // the numbers as written, the unknown keys kept
        XCTAssertEqual(after["bgBrakeISFweight"], "0.1")
        XCTAssertEqual(after["sensorDays"], "3.3")
        XCTAssertEqual(after["weight"], "81.299999999999997")
        XCTAssertEqual(after["aKeyThisBuildDoesNotKnow.values[1]"], "3.3")
        XCTAssertEqual(after["aKeyThisBuildDoesNotKnow.values[4].deep"], "0.7")
        XCTAssertEqual(after["anotherUnknownKey"], "null")
        // read as the settings
        let settings = try await stored(files)
        XCTAssertEqual(settings.bgBrakeISFweight, Decimal(string: "0.1"))
        XCTAssertEqual(settings.autoisf_max, Decimal(string: "1.35"))
        XCTAssertEqual(settings.birthDate, day(1985, 3, 14))
        XCTAssertEqual(settings.sexSetting, 1)
    }

    /// A birth date already a day is not written (its text as it was, here without the milliseconds); a file without
    /// the sex or the birth date shares neither and gets no birth date.
    func testStartMigrationWritesOnlyWhatChanges() async throws {
        let kept = IsolatedFileStorage()
        await kept.save(
            #"{ "sexSetting" : 3, "birthDate" : "1990-01-01T12:00:00Z", "minimumSMB" : 0.15 }"#,
            as: OpenAPS.FreeAPS.settings
        )
        await migrate(kept)
        let keptRaw = await kept.retrieveRaw(OpenAPS.FreeAPS.settings)
        let keptAfter = try JSONLiterals.of(XCTUnwrap(keptRaw))
        XCTAssertEqual(keptAfter["birthDate"], #""1990-01-01T12:00:00Z""#)
        XCTAssertEqual(keptAfter["sexSetting"], "3")
        XCTAssertEqual(keptAfter["minimumSMB"], "0.15")
        XCTAssertEqual(keptAfter["shareSex"], "false")
        XCTAssertEqual(keptAfter["shareAge"], "true")
        XCTAssertEqual(keptAfter["demographicsSharingMigrated"], "true")

        let none = IsolatedFileStorage()
        await none.save(#"{ "insulinReqPercentage" : 70.5 }"#, as: OpenAPS.FreeAPS.settings)
        await migrate(none)
        let noneRaw = await none.retrieveRaw(OpenAPS.FreeAPS.settings)
        let noneAfter = try JSONLiterals.of(XCTUnwrap(noneRaw))
        XCTAssertEqual(noneAfter, [
            "": "{",
            "insulinReqPercentage": "70.5",
            "shareSex": "false",
            "shareAge": "false",
            "demographicsSharingMigrated": "true"
        ])
    }

    /// Once: the key written, the next starts leave the file as it is, a toggle turned off since stays off, and a value
    /// set since starts not shared. A file with the key (a fresh install's, a restored older backup's: false) is never
    /// migrated.
    func testStartMigrationRunsOnce() async throws {
        let files = IsolatedFileStorage()
        try await saveOlderFile(settings(sex: 0), to: files)
        await migrate(files)
        var migrated = try await stored(files)
        XCTAssertTrue(migrated.shareSex)

        migrated.shareSex = false
        migrated.birthDate = day(1985, 3, 1)
        await files.save(migrated, as: OpenAPS.FreeAPS.settings)
        let saved = await files.retrieveRaw(OpenAPS.FreeAPS.settings)
        await migrate(files)
        let again = await files.retrieveRaw(OpenAPS.FreeAPS.settings)
        XCTAssertEqual(again, saved)
        let restarted = try await stored(files)
        XCTAssertFalse(restarted.shareSex)
        XCTAssertFalse(restarted.shareAge)

        // the key there, false
        let fresh = IsolatedFileStorage()
        var unmigrated = settings(sex: 1, birthDate: day(1985, 3, 1))
        unmigrated.demographicsSharingMigrated = false
        await fresh.save(unmigrated, as: OpenAPS.FreeAPS.settings)
        let freshSaved = await fresh.retrieveRaw(OpenAPS.FreeAPS.settings)
        await migrate(fresh)
        let freshAfter = await fresh.retrieveRaw(OpenAPS.FreeAPS.settings)
        XCTAssertEqual(freshAfter, freshSaved)
        let freshSettings = try await stored(fresh)
        XCTAssertFalse(freshSettings.shareSex)
        XCTAssertFalse(freshSettings.demographicsSharingMigrated)
    }

    /// No file (a fresh install): none written. A file that is not a JSON object: left as it is.
    func testStartMigrationWithoutASettingsFile() async throws {
        let none = IsolatedFileStorage()
        await migrate(none)
        let noneAfter = await none.retrieveRaw(OpenAPS.FreeAPS.settings)
        XCTAssertNil(noneAfter)

        for raw in ["not json {", "[1, 2]", "\"text\""] {
            let files = IsolatedFileStorage()
            await files.save(raw, as: OpenAPS.FreeAPS.settings)
            await migrate(files)
            let after = await files.retrieveRaw(OpenAPS.FreeAPS.settings)
            XCTAssertEqual(after, raw)
        }
    }

    // MARK: - A value cleared turns its toggle off (Settings › Demographics, the Reference intakes sheet)

    func testClearingAValueTurnsItsToggleOff() {
        let shared = DemographicsSharing(sexSetting: 0, birthDate: day(1985, 3, 14), shareSex: true, shareAge: true)
        XCTAssertEqual(shared.settingSex(1), DemographicsSharing(
            sexSetting: 1,
            birthDate: day(1985, 3, 14),
            shareSex: true,
            shareAge: true
        ))
        // Other is a value set
        XCTAssertTrue(shared.settingSex(2).shareSex)
        let sexCleared = shared.settingSex(3)
        XCTAssertEqual(sexCleared.sexSetting, 3)
        XCTAssertFalse(sexCleared.shareSex)
        XCTAssertTrue(sexCleared.shareAge, "the other toggle left as it is")

        XCTAssertEqual(shared.settingBirthDate(day(1990, 1, 1)).birthDate, day(1990, 1, 1))
        XCTAssertTrue(shared.settingBirthDate(day(1990, 1, 1)).shareAge)
        let birthCleared = shared.settingBirthDate(.distantPast)
        XCTAssertEqual(birthCleared.birthDate, .distantPast)
        XCTAssertFalse(birthCleared.shareAge)
        XCTAssertTrue(birthCleared.shareSex, "the other toggle left as it is")

        // setting the values again doesn't share them
        let again = shared.settingSex(3).settingBirthDate(.distantPast).settingSex(0).settingBirthDate(day(1985, 3, 14))
        XCTAssertFalse(again.sharesSex)
        XCTAssertFalse(again.sharesAge)
        // a toggle off stays off
        let off = DemographicsSharing(sexSetting: 0, birthDate: day(1985, 3, 14))
        XCTAssertFalse(off.settingSex(1).shareSex)
        XCTAssertFalse(off.settingBirthDate(day(1990, 1, 1)).shareAge)
    }

    /// The update the screens write: the four demographics fields together, every other setting as it is.
    func testDemographicsUpdateWritesOnlyTheDemographics() {
        var current = settings(sex: 1, birthDate: day(1985, 3, 14), weight: 80, height: 180, uploadStats: true)
        current.shareSex = true
        current.shareAge = true
        current.weightInLb = true
        var updated = current
        updated.demographics = current.demographics.settingSex(3).settingBirthDate(.distantPast)
        XCTAssertEqual(updated.sexSetting, 3)
        XCTAssertEqual(updated.birthDate, .distantPast)
        XCTAssertFalse(updated.shareSex)
        XCTAssertFalse(updated.shareAge)
        var expected = current
        expected.sexSetting = 3
        expected.birthDate = .distantPast
        expected.shareSex = false
        expected.shareAge = false
        XCTAssertEqual(updated, expected)
        XCTAssertEqual(updated.demographics, DemographicsSharing(sexSetting: 3))

        // the Reference intakes sheet's Save: Woman or Man and a birth date, the toggles as they are
        var sheet = current
        sheet.demographics = current.demographics.settingSex(0).settingBirthDate(day(1990, 1, 1))
        XCTAssertEqual(sheet.demographics, DemographicsSharing(
            sexSetting: 0,
            birthDate: day(1990, 1, 1),
            shareSex: true,
            shareAge: true
        ))
    }

    // MARK: - The birth date read as a day

    /// A stored value not kept as a day (a restored older backup, the raw editor) reads as its day, writing nothing:
    /// the texts, the wheel, the upload, the age (the Daily Log gate, the reference intakes) all read it so. A day kept
    /// reads as it is in every zone (UTC+12 too, where 12:00 UTC is a midnight, unlike the migration's rule).
    func testBirthDateIsReadAsADay() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        // the old picker's midnight of 14 March 1985 in Berlin: the 13th in UTC
        let legacy = midnight(1985, 3, 14, in: Self.berlin)
        XCTAssertEqual(DemographicsSharing.birthDay(legacy, timeZone: Self.berlin), day(1985, 3, 14))
        XCTAssertEqual(DemographicsSharing.birthDay(legacy, timeZone: newYork), day(1985, 3, 14))
        // the raw editor's 06:00 UTC
        XCTAssertEqual(
            DemographicsSharing.birthDay(day(1985, 3, 14).addingTimeInterval(-TimeInterval.hours(6)), timeZone: newYork),
            day(1985, 3, 14)
        )
        // kept as a day: as it is in every zone, a JSON round trip's milliseconds included
        let drifted = day(1990, 1, 1).addingTimeInterval(0.002)
        for hours in [-12, -5, 0, 1, 12, 14] {
            XCTAssertEqual(DemographicsSharing.birthDay(day(1990, 1, 1), timeZone: zone(hours)), day(1990, 1, 1), "UTC\(hours)")
            XCTAssertEqual(DemographicsSharing.birthDay(drifted, timeZone: zone(hours)), drifted, "UTC\(hours)")
        }
        XCTAssertEqual(DemographicsSharing.legacyBirthDay(day(1990, 1, 1), timeZone: zone(12)), day(1990, 1, 2))
        XCTAssertEqual(DemographicsSharing.birthDay(.distantPast), .distantPast)

        // the readers
        let values = DemographicsSharing(sexSetting: 0, birthDate: legacy, shareSex: true, shareAge: true)
        XCTAssertEqual(Demographics.bornShortText(legacy), Demographics.bornShortText(day(1985, 3, 14)))
        XCTAssertEqual(Demographics.bornText(legacy), Demographics.bornText(day(1985, 3, 14)))
        XCTAssertEqual(values.shownBirthDay, day(1985, 3, 14))
        XCTAssertNil(DemographicsSharing(sexSetting: 0).shownBirthDay)
        XCTAssertEqual(values.statisticsBirthDate, day(1985, 3, 14))
        XCTAssertEqual(values.birthDate, legacy, "stored as it is")
        // the birthday is the 14th in New York (read in UTC as stored, it was the 13th)
        var phone = Calendar(identifier: .gregorian)
        phone.timeZone = newYork
        let birthday = midnight(2026, 3, 14, in: newYork)
        let dayBefore = birthday.addingTimeInterval(-TimeInterval.minutes(30))
        let onTheDay = birthday.addingTimeInterval(.minutes(30))
        XCTAssertEqual(DemographicsSharing.age(birthDate: legacy, now: dayBefore, calendar: phone), 40)
        XCTAssertEqual(DemographicsSharing.age(birthDate: legacy, now: onTheDay, calendar: phone), 41)
        XCTAssertEqual(NutrientReferences(.init(sexSetting: 0, birthDate: legacy), now: dayBefore, calendar: phone)?.age, 40)
        XCTAssertEqual(NutrientReferences(.init(sexSetting: 0, birthDate: legacy), now: onTheDay, calendar: phone)?.age, 41)
        XCTAssertTrue(values.qualifiesForLogs(now: now, calendar: phone))
    }

    // MARK: - The birth date across time zones

    /// A day kept at 12:00 UTC reads as that day in every zone: entered in UTC+1, the 1 January shown, the age and the
    /// uploaded date are those of 1 January wherever the phone is later (UTC−5, UTC−12, UTC+14). Each case runs with
    /// the phone's zone the default one (what a `DateFormatter` and `Calendar.current` read) and passes it where the
    /// code takes it (`TimeZone.current` doesn't follow the default zone).
    func testBirthDateIsADayInEveryTimeZone() throws {
        let defaultZone = NSTimeZone.default
        defer { NSTimeZone.default = defaultZone }
        // the wheel (shown in UTC) picks 1 January 1990 while the phone is in UTC+1
        let picked = DemographicsSharing.birthDate(day: day(1990, 1, 1).addingTimeInterval(.hours(5)))
        XCTAssertEqual(picked, day(1990, 1, 1))
        XCTAssertTrue(DemographicsSharing.isKeptAsDay(picked))

        for hours in [1, -5, -12, 14] {
            let phone = zone(hours)
            NSTimeZone.default = phone
            XCTAssertEqual(Calendar.current.timeZone, phone, "the default zone is the phone's")
            var phoneCalendar = Calendar(identifier: .gregorian)
            phoneCalendar.timeZone = phone
            // shown as 1 January, as a formatter in the phone's zone shows its midnight of 1 January
            let local = DateFormatter()
            local.dateStyle = .medium
            local.timeStyle = .none
            XCTAssertEqual(
                Demographics.bornShortText(picked),
                local.string(from: midnight(1990, 1, 1, in: phone)),
                "UTC\(hours)"
            )
            // read as it is, whatever the phone's zone
            XCTAssertEqual(DemographicsSharing.birthDay(picked, timeZone: phone), picked, "UTC\(hours)")
            // the birthday starts at the phone's midnight
            let newYear = midnight(2026, 1, 1, in: phone)
            XCTAssertEqual(
                DemographicsSharing.age(
                    birthDate: picked,
                    now: newYear.addingTimeInterval(.minutes(30)),
                    calendar: phoneCalendar
                ),
                36,
                "UTC\(hours)"
            )
            XCTAssertEqual(
                DemographicsSharing.age(
                    birthDate: picked,
                    now: newYear.addingTimeInterval(-TimeInterval.minutes(30)),
                    calendar: phoneCalendar
                ),
                35,
                "UTC\(hours)"
            )
            // the upload's date is 1 January 1990 read in any zone from UTC−12 to UTC+11, the 2nd east of it: 1990
            let uploaded = DemographicsSharing(sexSetting: 0, birthDate: picked, shareAge: true).statisticsBirthDate
            XCTAssertEqual(phoneCalendar.component(.year, from: uploaded), 1990, "UTC\(hours)")
        }
    }

    /// The old date picker kept midnight in the zone it was entered in; at the migration (once) it becomes that day:
    /// midnight in the phone's zone is that day there, exactly 12:00 UTC is kept (this build's day), any other moment
    /// the UTC day 12 hours later (midnight from UTC−11 to UTC+11 wherever the phone is now). Read as before (in the phone's zone), 1 January 1990 entered in Berlin was
    /// 31 December 1989 in UTC−5.
    func testLegacyBirthDatesBecomeTheirDay() throws {
        func legacy(_ moment: Date, _ phone: TimeZone) -> Date {
            DemographicsSharing.legacyBirthDay(moment, timeZone: phone)
        }
        let auckland = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let pagoPago = try XCTUnwrap(TimeZone(identifier: "Pacific/Pago_Pago"))
        let saoPaulo = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))

        let berlinNewYear = midnight(1990, 1, 1, in: zone(1))
        var west = Calendar(identifier: .gregorian)
        west.timeZone = zone(-5)
        XCTAssertEqual(west.component(.year, from: berlinNewYear), 1989, "the drift")
        XCTAssertEqual(legacy(berlinNewYear, zone(1)), day(1990, 1, 1))
        XCTAssertEqual(legacy(berlinNewYear, zone(-5)), day(1990, 1, 1))

        // UTC+12: midnight in Auckland in winter (NZST) is 12:00 UTC of the day before: that day with the phone still
        // at UTC+12; elsewhere it is this build's 12:00 UTC, kept (the limit)
        let winter = midnight(1985, 7, 14, in: auckland)
        XCTAssertEqual(winter, day(1985, 7, 13))
        for phone in [auckland, zone(12)] {
            XCTAssertEqual(legacy(winter, phone), day(1985, 7, 14), phone.identifier)
        }
        for phone in [newYork, Self.berlin, zone(14)] {
            XCTAssertEqual(legacy(winter, phone), day(1985, 7, 13), "\(phone.identifier), the limit")
        }
        // UTC+13 (Auckland in summer, NZDT) and UTC+14: right in their own zone, a day early once the phone has left
        let summer = midnight(1985, 1, 14, in: auckland)
        XCTAssertEqual(legacy(summer, auckland), day(1985, 1, 14))
        XCTAssertEqual(legacy(summer, Self.berlin), day(1985, 1, 13), "the limit east of UTC+12")
        for hours in [13, 14] {
            let entered = midnight(1985, 3, 1, in: zone(hours))
            XCTAssertEqual(legacy(entered, zone(hours)), day(1985, 3, 1), "UTC+\(hours)")
            XCTAssertEqual(legacy(entered, Self.berlin), day(1985, 2, 28), "UTC+\(hours), the limit")
        }
        // UTC−11 wherever the phone is (but 24 hours east of it, UTC+13, where it is midnight too)
        let samoa = midnight(1985, 3, 1, in: pagoPago)
        for phone in [pagoPago, Self.berlin, newYork, zone(12), zone(-12)] {
            XCTAssertEqual(legacy(samoa, phone), day(1985, 3, 1), phone.identifier)
        }
        // UTC−12: midnight is 12:00 UTC of the day, kept as it is
        let bakerIsland = midnight(1985, 3, 1, in: zone(-12))
        XCTAssertEqual(legacy(bakerIsland, zone(-12)), day(1985, 3, 1))
        XCTAssertEqual(legacy(bakerIsland, Self.berlin), day(1985, 3, 1))

        // entered in Berlin, read at the first run in New York, and the other way round
        XCTAssertEqual(legacy(midnight(1985, 7, 14, in: Self.berlin), newYork), day(1985, 7, 14))
        XCTAssertEqual(legacy(midnight(1985, 7, 14, in: newYork), Self.berlin), day(1985, 7, 14))

        // a midnight DST skipped: the day started at 01:00 (São Paulo, 2 November 1985)
        let skipped = midnight(1985, 11, 2, in: saoPaulo)
        var saoPauloCalendar = Calendar(identifier: .gregorian)
        saoPauloCalendar.timeZone = saoPaulo
        XCTAssertEqual(saoPauloCalendar.component(.hour, from: skipped), 1, "no midnight that day")
        XCTAssertEqual(legacy(skipped, saoPaulo), day(1985, 11, 2))
        XCTAssertEqual(legacy(skipped, Self.berlin), day(1985, 11, 2))

        // a JSON round trip's millisecond either side of midnight
        XCTAssertEqual(legacy(berlinNewYear.addingTimeInterval(-0.002), zone(1)), day(1990, 1, 1))
        XCTAssertEqual(legacy(berlinNewYear.addingTimeInterval(0.002), zone(1)), day(1990, 1, 1))
        XCTAssertEqual(legacy(.distantPast, zone(1)), .distantPast)

        // through the migration, a toggle and the day together
        let migrated = settings(sex: 1, birthDate: winter).migratingDemographicsSharing(timeZone: auckland)
        XCTAssertEqual(migrated.birthDate, day(1985, 7, 14))
        XCTAssertTrue(migrated.shareAge)
    }

    /// After a downgrade dropped the key, the migration converts the birth date again: a day this build kept
    /// (12:00 UTC) is kept, but with the phone at UTC+12, where it is midnight of the next day (the limit). Read
    /// (`birthDay`), it is that day there too.
    func testBirthDateMigratedAgainAfterADowngrade() {
        let current = settings(sex: 0, birthDate: day(1990, 1, 1))
        for hours in [-12, -5, 0, 1, 11, 14] {
            XCTAssertEqual(
                current.migratingDemographicsSharing(timeZone: zone(hours)).birthDate,
                day(1990, 1, 1),
                "UTC\(hours)"
            )
        }
        XCTAssertEqual(current.migratingDemographicsSharing(timeZone: Self.berlin).birthDate, day(1990, 1, 1))
        XCTAssertEqual(
            current.migratingDemographicsSharing(timeZone: zone(12)).birthDate,
            day(1990, 1, 2),
            "UTC+12, the limit"
        )
        XCTAssertEqual(DemographicsSharing.birthDay(day(1990, 1, 1), timeZone: zone(12)), day(1990, 1, 1))
    }

    /// The wheel's range: 1 January 1920 to today, as days.
    func testBirthDateRange() {
        let range = DemographicsSharing.birthDateRange(now: now, timeZone: Self.berlin)
        XCTAssertEqual(range.lowerBound, day(1920, 1, 1))
        XCTAssertEqual(range.upperBound, day(2026, 11, 2))
    }

    // MARK: - The Statistics upload

    /// Not shared: `sex` 3 and `dob` `.distantPast`; shared: the sex, and the birth date as it is.
    func testStatisticsRedaction() throws {
        var values = DemographicsSharing(sexSetting: 0, birthDate: day(1985, 3, 14))
        XCTAssertEqual(values.statisticsSex, 3)
        XCTAssertEqual(values.statisticsBirthDate, .distantPast)

        values.shareSex = true
        values.shareAge = true
        XCTAssertEqual(values.statisticsSex, 0)
        XCTAssertEqual(values.statisticsBirthDate, day(1985, 3, 14))

        // the toggle left on without a value: nothing
        values.sexSetting = 3
        values.birthDate = .distantPast
        XCTAssertEqual(values.statisticsSex, 3)
        XCTAssertEqual(values.statisticsBirthDate, .distantPast)
        XCTAssertFalse(values.sharesSex)
        XCTAssertFalse(values.sharesAge)

        values.sexSetting = 2
        XCTAssertEqual(values.statisticsSex, 2)
    }

    /// The upload's encoding: the birth date, 1 January read as 1 January (it was the phone's midnight: 31 December
    /// in UTC east of it), sex as the setting.
    func testStatisticsEncoding() throws {
        let values = DemographicsSharing(sexSetting: 1, birthDate: day(1990, 1, 1), shareSex: true, shareAge: true)
        struct Upload: Encodable {
            let dob: Date
            let sex: Int
        }
        let data = try JSONCoding.encoder.encode(Upload(dob: values.statisticsBirthDate, sex: values.statisticsSex))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains(#""dob" : "1990-01-01T12:00:00"#), json)
        XCTAssertTrue(json.contains(#""sex" : 1"#), json)
    }

    // MARK: - The Daily Log gate

    func testDailyLogNeedsSexAndAgeShared() {
        let born = day(1985, 3, 1)
        func qualifies(_ sex: Int, _ birthDate: Date, shareSex: Bool = true, shareAge: Bool = true) -> Bool {
            DemographicsSharing(sexSetting: sex, birthDate: birthDate, shareSex: shareSex, shareAge: shareAge)
                .qualifiesForLogs(now: now, calendar: calendar)
        }
        XCTAssertTrue(qualifies(0, born))
        XCTAssertTrue(qualifies(1, born))
        XCTAssertFalse(qualifies(2, born))
        XCTAssertFalse(qualifies(3, born))
        XCTAssertFalse(qualifies(0, born, shareSex: false))
        XCTAssertFalse(qualifies(0, born, shareAge: false))
        XCTAssertFalse(qualifies(0, .distantPast))
        // under a year
        XCTAssertFalse(qualifies(0, day(2026, 6, 1)))
    }

    // MARK: - The age

    func testAge() {
        XCTAssertEqual(DemographicsSharing.age(birthDate: day(1985, 3, 1), now: now, calendar: calendar), 41)
        XCTAssertEqual(DemographicsSharing.age(birthDate: day(1985, 11, 3), now: now, calendar: calendar), 40)
        // the birthday today
        XCTAssertEqual(DemographicsSharing.age(birthDate: day(1985, 11, 2), now: now, calendar: calendar), 41)
        XCTAssertNil(DemographicsSharing.age(birthDate: .distantPast, now: now, calendar: calendar))
    }

    /// The phone's calendar may be another than the Gregorian (2026 is 2569 in the Buddhist one, Reiwa 8 in the
    /// Japanese, 1448 in the Islamic, 1405 in the Persian): the age is the same, and so are the Daily Log gate, the
    /// reference intakes that read it (it was 584 years in the Buddhist, −1977 in the Japanese).
    @MainActor func testAgeInAnyCalendar() throws {
        let identifiers: [Calendar.Identifier] = [.buddhist, .japanese, .islamic, .islamicUmmAlQura, .persian]
        for identifier in identifiers {
            var phone = Calendar(identifier: identifier)
            phone.timeZone = Self.berlin
            XCTAssertNotEqual(phone.component(.year, from: now), 2026, "\(identifier)")
            XCTAssertEqual(DemographicsSharing.age(birthDate: day(1985, 3, 1), now: now, calendar: phone), 41, "\(identifier)")
            XCTAssertEqual(DemographicsSharing.age(birthDate: day(1985, 11, 3), now: now, calendar: phone), 40, "\(identifier)")
            XCTAssertEqual(DemographicsSharing.age(birthDate: day(1985, 11, 2), now: now, calendar: phone), 41, "\(identifier)")

            XCTAssertTrue(
                DemographicsSharing(sexSetting: 0, birthDate: day(1985, 3, 1), shareSex: true, shareAge: true)
                    .qualifiesForLogs(now: now, calendar: phone),
                "\(identifier)"
            )
            let references = NutrientReferences(.init(sexSetting: 1, birthDate: day(1985, 3, 1)), now: now, calendar: phone)
            XCTAssertEqual(references?.age, 41, "\(identifier)")
        }
        // the birthday still starts at the phone's midnight, in its zone
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = zone(-5)
        let newYear = midnight(2026, 1, 1, in: zone(-5))
        XCTAssertEqual(
            DemographicsSharing.age(
                birthDate: day(1990, 1, 1),
                now: newYear.addingTimeInterval(.minutes(30)),
                calendar: buddhist
            ),
            36
        )
        XCTAssertEqual(
            DemographicsSharing.age(
                birthDate: day(1990, 1, 1),
                now: newYear.addingTimeInterval(-TimeInterval.minutes(30)),
                calendar: buddhist
            ),
            35
        )
    }

    // MARK: - Settings › Demographics, the Reference intakes sheet

    /// Save needs Woman or Man and the birth date.
    func testReferenceIntakesSave() {
        let born = day(1985, 3, 14)
        XCTAssertTrue(DemographicsSharing.canSaveReferenceIntakes(sex: .woman, birthDate: born))
        XCTAssertTrue(DemographicsSharing.canSaveReferenceIntakes(sex: .man, birthDate: born))
        XCTAssertFalse(DemographicsSharing.canSaveReferenceIntakes(sex: .other, birthDate: born))
        XCTAssertFalse(DemographicsSharing.canSaveReferenceIntakes(sex: .secret, birthDate: born))
        XCTAssertFalse(DemographicsSharing.canSaveReferenceIntakes(sex: .woman, birthDate: nil))
        XCTAssertFalse(DemographicsSharing.canSaveReferenceIntakes(sex: .woman, birthDate: .distantPast))
    }

    /// The wheel opens on 1 January 30 years ago without setting it; "Set to 1 Jan 1996" under it takes that day as
    /// it is (someone born then needn't turn the wheel away and back), and Save is enabled with it.
    func testBirthWheelStartIsADayToSet() {
        let start = DemographicsSharing.birthWheelStart(now: now, timeZone: Self.berlin)
        XCTAssertEqual(start, day(1996, 1, 1))
        XCTAssertEqual(DemographicsSharing.birthDate(day: start), start, "set as shown")
        XCTAssertFalse(DemographicsSharing.canSaveReferenceIntakes(sex: .woman, birthDate: nil), "untouched")
        XCTAssertTrue(
            DemographicsSharing
                .canSaveReferenceIntakes(sex: .woman, birthDate: DemographicsSharing.birthDate(day: start))
        )
        XCTAssertTrue(DemographicsSharing.birthDateRange(now: now, timeZone: Self.berlin).contains(start))
    }

    func testReferenceIntakesFooterAndSummary() {
        XCTAssertTrue(DemographicsSharing(sexSetting: 0, birthDate: day(1985, 3, 1)).setsReferenceIntakes)
        XCTAssertFalse(DemographicsSharing(sexSetting: 2, birthDate: day(1985, 3, 1)).setsReferenceIntakes)
        XCTAssertFalse(DemographicsSharing(sexSetting: 1).setsReferenceIntakes)

        let set = DemographicsSharing(sexSetting: 0, birthDate: day(1985, 3, 1))
        XCTAssertEqual(set.summary(uploading: true), "Nothing shared")
        var shared = set
        shared.shareSex = true
        XCTAssertEqual(shared.summary(uploading: true), "Sex shared")
        shared.shareAge = true
        XCTAssertEqual(shared.summary(uploading: true), "Sex and age shared")
        shared.shareSex = false
        XCTAssertEqual(shared.summary(uploading: true), "Age shared")
        // a toggle on without its value shares nothing
        var unset = DemographicsSharing(shareSex: true, shareAge: true)
        XCTAssertEqual(unset.summary(uploading: true), "Nothing shared")
        unset.sexSetting = 2
        XCTAssertEqual(unset.summary(uploading: true), "Sex shared")
        // Online Backup and Statistics off: nothing is uploaded, whatever the toggles
        XCTAssertEqual(unset.summary(uploading: false), "Off")
        XCTAssertEqual(shared.summary(uploading: false), "Off")
        XCTAssertEqual(set.summary(uploading: false), "Off")
    }

    // MARK: - The height in feet and inches

    func testFeetAndInches() {
        XCTAssertEqual(Demographics.feetInches(cm: 172).feet, 5)
        XCTAssertEqual(Demographics.feetInches(cm: 172).inches, 8)
        // 71.9 in rounds to 6 ft 0 in, not 5 ft 12 in
        XCTAssertEqual(Demographics.feetInches(cm: 182.6).feet, 6)
        XCTAssertEqual(Demographics.feetInches(cm: 182.6).inches, 0)
        XCTAssertEqual(Demographics.cm(feet: 5, inches: 8), Decimal(string: "172.72"), "exact")
    }

    /// Opening the screen in ft/in fills the fields from 172 cm (5 ft 8 in): committing them as they are keeps 172 cm
    /// (it became 172.72); an edit writes the new height; 0 ft 0 in is not set.
    func testFeetAndInchesKeepTheHeightTheyCameFrom() {
        XCTAssertEqual(Demographics.height(feet: 5, inches: 8, keeping: 172), 172)
        XCTAssertEqual(Demographics.height(feet: 5, inches: 9, keeping: 172), Decimal(string: "175.26"))
        XCTAssertEqual(Demographics.height(feet: 5, inches: 8, keeping: 0), Decimal(string: "172.72"))
        XCTAssertEqual(Demographics.height(feet: 0, inches: 0, keeping: 172), 0)
        XCTAssertEqual(Demographics.height(feet: 0, inches: 0, keeping: 0), 0)
    }
}

/// `DataMigrations`' JSON file helpers (`updateJSONObject`, `renameField`, `normalizeGlucoseSmoothingSettings`): a value
/// they don't change keeps its text as the app writes it, numbers included (JSONSerialization wrote 0.1 as
/// 0.10000000000000001), and its value in the forms the app doesn't write (`1e-7`, `1.0`, `-0`); a file with a number
/// out of `Decimal`'s range is left as it is (the versioned rename throws).
final class DataMigrationsJSONTests: XCTestCase {
    private static let numbers = """
    {
      "units" : "mg/dL",
      "closedLoop" : true,
      "smoothGlucose" : true,
      "insulinReqPercentage" : 70.5,
      "autoisf_max" : 1.35,
      "smbDeliveryRatioMin" : 0.65,
      "minimumSMB" : 0.15,
      "bgBrakeISFweight" : 0.1,
      "sensorDays" : 3.3,
      "individualAdjustmentFactor" : 0.7,
      "weight" : 81.299999999999997,
      "timeCap" : 8,
      "nested" : {
        "values" : [
          0.1,
          3.3,
          null,
          {
            "deep" : 0.7
          }
        ],
        "none" : null,
        "on" : false
      }
    }
    """

    private static let preferences = """
    {
      "max_iob" : 0,
      "max_daily_safety_multiplier" : 3,
      "current_basal_safety_multiplier" : 4,
      "autosens_max" : 1.2,
      "autosens_min" : 0.7,
      "resistanceLowersTarget" : true,
      "curve" : "rapid-acting",
      "adjustmentFactor" : 0.65,
      "bolus_increment" : 0.1,
      "maxDelta_bg_threshold" : 0.2,
      "noisyCGMTargetMultiplier" : 1.3,
      "smb_delivery_ratio" : 0.5,
      "insulinPeakTime" : 75,
      "threshold_setting" : 3.3
    }
    """

    private func literals(_ files: IsolatedFileStorage, _ file: String) async throws -> [String: String] {
        let raw = await files.retrieveRaw(file)
        return try JSONLiterals.of(XCTUnwrap(raw))
    }

    /// Nothing to do: the file isn't written. Written back unchanged, or with one key edited: every other value has
    /// its text.
    func testUpdateJSONObjectKeepsEveryNumber() async throws {
        let file = OpenAPS.FreeAPS.settings
        let files = IsolatedFileStorage()
        await files.save(Self.numbers, as: file)
        let before = try JSONLiterals.of(Self.numbers)

        try await DataMigrations.updateJSONObject(inFile: file, storage: files) { _ in false }
        let untouched = await files.retrieveRaw(file)
        XCTAssertEqual(untouched, Self.numbers)

        try await DataMigrations.updateJSONObject(inFile: file, storage: files) { _ in true }
        let rewritten = try await literals(files, file)
        XCTAssertEqual(rewritten, before)
        XCTAssertEqual(rewritten["bgBrakeISFweight"], "0.1")
        XCTAssertEqual(rewritten["sensorDays"], "3.3")
        XCTAssertEqual(rewritten["nested.values[1]"], "3.3")

        try await DataMigrations.updateJSONObject(inFile: file, storage: files) { dict in
            dict["closedLoop"] = .bool(false)
            return true
        }
        var expected = before
        expected["closedLoop"] = "false"
        let edited = try await literals(files, file)
        XCTAssertEqual(edited, expected)
    }

    /// `smoothGlucose` on becomes `glucoseSmoothing` Savitzky–Golay, 3 passes, as before; every other number as it was;
    /// once done (or with `smoothGlucose` off), the file isn't written.
    func testGlucoseSmoothingNormalizationKeepsEveryNumber() async throws {
        let file = OpenAPS.FreeAPS.settings
        let files = IsolatedFileStorage()
        await files.save(Self.numbers, as: file)
        let before = try JSONLiterals.of(Self.numbers)

        try await DataMigrations.normalizeGlucoseSmoothingSettings(storage: files)
        let after = try await literals(files, file)
        var expected = before
        expected["glucoseSmoothing"] = "{"
        expected["glucoseSmoothing.algorithm"] = #""savitzkyGolay""#
        expected["glucoseSmoothing.savitzkyGolay"] = "{"
        expected["glucoseSmoothing.savitzkyGolay.passes"] = "3"
        XCTAssertEqual(after, expected)
        let settings = await files.retrieve(file, as: FreeAPSSettings.self)
        XCTAssertEqual(settings?.glucoseSmoothing.algorithm, .savitzkyGolay)
        XCTAssertEqual(settings?.glucoseSmoothing.savitzkyGolay.passes, .three)
        XCTAssertEqual(settings?.bgBrakeISFweight, Decimal(string: "0.1"))

        let normalized = await files.retrieveRaw(file)
        try await DataMigrations.normalizeGlucoseSmoothingSettings(storage: files)
        let again = await files.retrieveRaw(file)
        XCTAssertEqual(again, normalized)

        let off = IsolatedFileStorage()
        let smoothingOff = Self.numbers.replacingOccurrences(of: #""smoothGlucose" : true"#, with: #""smoothGlucose" : false"#)
        await off.save(smoothingOff, as: file)
        try await DataMigrations.normalizeGlucoseSmoothingSettings(storage: off)
        let offAfter = await off.retrieveRaw(file)
        XCTAssertEqual(offAfter, smoothingOff)
    }

    /// The 0 → 1 step's rename in preferences.json: the value moved, every other number as it was; once done, the
    /// file isn't written.
    func testRenameFieldKeepsEveryNumber() async throws {
        let file = OpenAPS.Settings.preferences
        let files = IsolatedFileStorage()
        await files.save(Self.preferences, as: file)
        let before = try JSONLiterals.of(Self.preferences)

        try await DataMigrations.renameField(
            from: "resistanceLowersTarget",
            to: "resistance_lowers_target",
            inFile: file,
            storage: files
        )
        let after = try await literals(files, file)
        var expected = before
        expected["resistanceLowersTarget"] = nil
        expected["resistance_lowers_target"] = "true"
        XCTAssertEqual(after, expected)
        XCTAssertEqual(after["bolus_increment"], "0.1")
        XCTAssertEqual(after["threshold_setting"], "3.3")

        let renamed = await files.retrieveRaw(file)
        try await DataMigrations.renameField(
            from: "resistanceLowersTarget",
            to: "resistance_lowers_target",
            inFile: file,
            storage: files
        )
        let again = await files.retrieveRaw(file)
        XCTAssertEqual(again, renamed)
    }

    /// Number forms none of the app's encoders write: an exponent form, trailing zeros, `-0`.
    private static let numberForms = """
    {
      "small" : 1e-7,
      "large" : 2.5E3,
      "signedExponent" : 25e-1,
      "negativeExponent" : -1.5e-3,
      "one" : 1.0,
      "trailingZero" : 0.150,
      "negativeZero" : -0,
      "negativeZeroFraction" : -0.0,
      "values" : [
        1e2,
        3.30
      ]
    }
    """

    /// Each keeps its value (compared as a `Decimal`), its text written out: `1e-7` as `0.0000001`, `1.0` as `1`, `-0`
    /// as `0`.
    func testUpdateJSONObjectKeepsTheValueOfOtherNumberForms() async throws {
        let file = OpenAPS.FreeAPS.settings
        let files = IsolatedFileStorage()
        await files.save(Self.numberForms, as: file)
        let before = try JSONLiterals.of(Self.numberForms)

        try await DataMigrations.updateJSONObject(inFile: file, storage: files) { _ in true }
        let after = try await literals(files, file)
        XCTAssertEqual(Set(after.keys), Set(before.keys))
        for (path, text) in before {
            let written = try XCTUnwrap(after[path], path)
            if text == "{" || text == "[" {
                XCTAssertEqual(written, text, path)
            } else {
                let value = try XCTUnwrap(Decimal(string: text), path)
                XCTAssertEqual(Decimal(string: written), value, path)
            }
        }
        XCTAssertEqual(after["small"], "0.0000001")
        XCTAssertEqual(after["large"], "2500")
        XCTAssertEqual(after["one"], "1")
        XCTAssertEqual(after["trailingZero"], "0.15")
        XCTAssertEqual(after["negativeZero"], "0")
        XCTAssertEqual(after["negativeZeroFraction"], "0")
        XCTAssertEqual(after["values[0]"], "100")
    }

    /// A number out of `Decimal`'s range, which JSONSerialization read: the 0 → 1 step's rename throws (the step isn't
    /// recorded as done without it), the file as it was.
    func testRenameFieldThrowsOnANumberOutOfRange() async throws {
        let file = OpenAPS.Settings.preferences
        let files = IsolatedFileStorage()
        let outOfRange = Self.preferences.replacingOccurrences(of: #""max_iob" : 0,"#, with: #""max_iob" : 1e130,"#)
        XCTAssertNotEqual(outOfRange, Self.preferences)
        await files.save(outOfRange, as: file)

        do {
            try await DataMigrations.renameField(
                from: "resistanceLowersTarget",
                to: "resistance_lowers_target",
                inFile: file,
                storage: files
            )
            XCTFail("renamed a field in a file it could not read")
        } catch {}
        let after = await files.retrieveRaw(file)
        XCTAssertEqual(after, outOfRange)
    }

    /// The per-start normalizations, on a settings file with a number out of `Decimal`'s range: the file as it was
    /// (the smoothing one throws, the start logs it; the demographics one logs it).
    func testNormalizationsLeaveAFileWithANumberOutOfRangeAsItIs() async throws {
        let file = OpenAPS.FreeAPS.settings
        let files = IsolatedFileStorage()
        let outOfRange = Self.numbers.replacingOccurrences(of: #""timeCap" : 8,"#, with: #""timeCap" : 1e130,"#)
        XCTAssertNotEqual(outOfRange, Self.numbers)
        await files.save(outOfRange, as: file)

        do {
            try await DataMigrations.normalizeGlucoseSmoothingSettings(storage: files)
            XCTFail("normalized a file it could not read")
        } catch {}
        let afterSmoothing = await files.retrieveRaw(file)
        XCTAssertEqual(afterSmoothing, outOfRange)

        await DataMigrations.migrateDemographicsSharing(storage: files)
        let afterDemographics = await files.retrieveRaw(file)
        XCTAssertEqual(afterDemographics, outOfRange)
    }

    /// No file, or one that is not a JSON object (not JSON, an array, even one with a number out of range): nothing to
    /// migrate, not an error; the file as it was.
    func testUpdateJSONObjectSkipsAFileThatIsNotAJSONObject() async throws {
        let file = OpenAPS.Settings.preferences
        let missing = IsolatedFileStorage()
        try await DataMigrations.updateJSONObject(inFile: file, storage: missing) { _ in
            XCTFail("transformed a missing file")
            return true
        }
        let none = await missing.retrieveRaw(file)
        XCTAssertNil(none)

        for text in ["not json", #"{ "max_iob" : "#, "[1, 2]", "[1e130]"] {
            let files = IsolatedFileStorage()
            await files.save(text, as: file)
            try await DataMigrations.updateJSONObject(inFile: file, storage: files) { _ in
                XCTFail("transformed \(text)")
                return true
            }
            let after = await files.retrieveRaw(file)
            XCTAssertEqual(after, text)
        }
    }
}

/// Every value of a JSON text as its literal text, by its path (`glucoseSmoothing.kalman`, `values[2]`): a number as
/// written (compared as text, not as a Double), a string with its quotes, an object or an array as `{` or `[` (so an
/// empty one is there too).
private struct JSONLiterals {
    private let bytes: [UInt8]
    private var index = 0
    private var literals: [String: String] = [:]

    private struct Malformed: Error {}

    private init(_ text: String) {
        bytes = Array(text.utf8)
    }

    static func of(_ text: String) throws -> [String: String] {
        var scanner = JSONLiterals(text)
        try scanner.value(at: "")
        scanner.skipSpace()
        guard scanner.index == scanner.bytes.count else { throw Malformed() }
        return scanner.literals
    }

    private mutating func skipSpace() {
        while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) {
            index += 1
        }
    }

    private mutating func next() throws -> UInt8 {
        skipSpace()
        guard index < bytes.count else { throw Malformed() }
        index += 1
        return bytes[index - 1]
    }

    private mutating func peek() throws -> UInt8 {
        skipSpace()
        guard index < bytes.count else { throw Malformed() }
        return bytes[index]
    }

    /// The text of a string, its quotes and escapes as written.
    private mutating func string() throws -> String {
        guard try next() == UInt8(ascii: "\"") else { throw Malformed() }
        let start = index - 1
        while index < bytes.count, bytes[index] != UInt8(ascii: "\"") {
            index += bytes[index] == UInt8(ascii: "\\") ? 2 : 1
        }
        guard index < bytes.count else { throw Malformed() }
        index += 1
        return String(decoding: bytes[start ..< index], as: UTF8.self)
    }

    private mutating func value(at path: String) throws {
        switch try peek() {
        case UInt8(ascii: "{"):
            literals[path] = "{"
            index += 1
            if try peek() == UInt8(ascii: "}") {
                index += 1
                return
            }
            repeat {
                let key = String(try string().dropFirst().dropLast())
                guard try next() == UInt8(ascii: ":") else { throw Malformed() }
                try value(at: path.isEmpty ? key : path + "." + key)
            } while try next() == UInt8(ascii: ",")
            guard bytes[index - 1] == UInt8(ascii: "}") else { throw Malformed() }
        case UInt8(ascii: "["):
            literals[path] = "["
            index += 1
            if try peek() == UInt8(ascii: "]") {
                index += 1
                return
            }
            var count = 0
            repeat {
                try value(at: path + "[\(count)]")
                count += 1
            } while try next() == UInt8(ascii: ",")
            guard bytes[index - 1] == UInt8(ascii: "]") else { throw Malformed() }
        case UInt8(ascii: "\""):
            literals[path] = try string()
        default:
            let start = index
            while index < bytes.count, !Array(",]} \n\r\t".utf8).contains(bytes[index]) {
                index += 1
            }
            guard index > start else { throw Malformed() }
            literals[path] = String(decoding: bytes[start ..< index], as: UTF8.self)
        }
    }
}
