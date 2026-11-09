import CoreData
@testable import FreeAPS
import HealthKit
import NightscoutKit
import XCTest

/// The CGM's `device` on iAPS's Nightscout uploads (`NightscoutCGMDevice.format`, the re-upload of the stored
/// readings) and the read-only backfill naming the CGM of Unknown readings from Nightscout entries
/// (`NightscoutCGMDevice.parse`, `NightscoutCGMSessions`, `NightscoutCGMBackfill`).
final class NightscoutCGMTests: XCTestCase {
    // MARK: - Fixtures

    private static let t0 = StatsFixtures.day0
    private static let all = DateInterval(start: .distantPast, end: .distantFuture)

    /// `t0` plus the minutes
    private func at(_ minutes: Double) -> Date {
        Self.t0.addingTimeInterval(.minutes(minutes))
    }

    private func device(
        name: String?,
        manufacturer: String?,
        model: String?,
        firmware: String? = nil,
        hardware: String? = nil,
        software: String? = nil,
        local: String? = nil,
        udi: String? = nil
    ) -> HKDevice {
        HKDevice(
            name: name,
            manufacturer: manufacturer,
            model: model,
            hardwareVersion: hardware,
            firmwareVersion: firmware,
            softwareVersion: software,
            localIdentifier: local,
            udiDeviceIdentifier: udi
        )
    }

    /// Entries with the device every `every` minutes over `[from, to]`.
    private func entries(
        _ device: String,
        _ from: Double,
        _ to: Double,
        every: Double = 5
    ) -> [NightscoutCGMSessions.Entry] {
        stride(from: from, through: to, by: every).map { NightscoutCGMSessions.Entry(date: at($0), device: device) }
    }

    private func snapshot(_ cgmId: String, plugin: String, name: String, device: String? = nil) -> CGMSnapshot {
        CGMSnapshot(
            plugin: plugin,
            cgmId: cgmId,
            name: name,
            sensorStart: nil,
            expectedLife: nil,
            oneMinute: false,
            sensorId: nil,
            device: device
        )
    }

    private func session(
        _ from: Double,
        _ to: Double?,
        _ source: CGMSessionSource,
        cgmId: String = "dexcomG6",
        device: String? = nil
    ) -> CGMSessionRecord {
        CGMSessionRecord(
            id: UUID(),
            start: at(from),
            end: to.map { at($0) },
            snapshot(cgmId, plugin: "DexG6Transmitter", name: "Dexcom G6", device: device),
            source: source
        )
    }

    private func spans(_ sessions: [CGMSessionRecord]) -> [[Date?]] {
        sessions.map { [$0.start, $0.end] }
    }

    // MARK: - The device string iAPS uploads

    /// Each plugin family's `HKDevice` as iAPS uploads it (`KnownPlugins.nightscoutDevice`): Loop's "<manufacturer>
    /// <model> <id>", the firmware never in it; one string for a sensor however its device changes (LibreLoop's model
    /// known later, LibreTransmitter's bridge maker known on connecting); the G7's and LibreLoop's id the reading's own.
    /// Each parses back to the CGM it came from.
    func testDeviceStringOfEachPluginFamily() {
        let cases: [(HKDevice, String, String?, String, String)] = [
            // CGMBLEKit: the transmitter's id is the name
            (
                device(name: "4XXXXX", manufacturer: "Dexcom", model: "G5 Mobile", software: "12", udi: "00386270000002"),
                "DexG5Transmitter", nil, "Dexcom G5 Mobile 4XXXXX", "dexcomG5"
            ),
            (
                device(name: "8XXXXX", manufacturer: "Dexcom", model: "G6", software: "12", udi: "00386270000385"),
                "DexG6Transmitter", nil, "Dexcom G6 8XXXXX", "dexcomG6"
            ),
            // G7SensorKit: the reading's sensor name (the manager's may be a newer sensor's), the firmware left out
            (
                device(name: "DXCMab", manufacturer: "Dexcom", model: "G7", firmware: "2.18.2.88", software: "CGMBLEKit1"),
                "G7CGMManager", "DXCMzz", "Dexcom G7 DXCMab", "dexcomG7"
            ),
            (
                device(name: "Unknown", manufacturer: "Dexcom", model: "G7", firmware: "2.18.2.88"),
                "G7CGMManager", "DXCMzz", "Dexcom G7 DXCMzz", "dexcomG7"
            ),
            (
                device(name: "DX02cd", manufacturer: "Dexcom", model: "ONE+", firmware: "2.18.2.88"),
                "G7CGMManager", nil, "Dexcom ONE+ DX02cd", "dexcomG7"
            ),
            // LibreTransmitter: the same string whatever the bridge's device says, the sensor's serial added
            (
                device(
                    name: "MiaomiaoClient", manufacturer: "Abbott", model: nil, firmware: "39", hardware: "A1",
                    local: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
                ),
                "LibreTransmitterManagerV3", "3MH00ABCDE", "Abbott LibreTransmitter 3MH00ABCDE", "libreTransmitter"
            ),
            (
                device(name: "MiaomiaoClient", manufacturer: "Tomato", model: nil),
                "LibreTransmitterManagerV3", "3MH00ABCDE", "Abbott LibreTransmitter 3MH00ABCDE", "libreTransmitter"
            ),
            (
                device(name: "MiaomiaoClient", manufacturer: "n/a", model: nil),
                "LibreTransmitterManagerV3", nil, "Abbott LibreTransmitter", "libreTransmitter"
            ),
            // LibreLoop: "Libre 3" before and after its model is known, the reading's serial
            (
                device(
                    name: "FreeStyle Libre 3 Plus", manufacturer: "Abbott", model: "Libre 3 Plus", firmware: "1.1",
                    local: "0D0000ABCD"
                ),
                "LibreLoopCGMManager", "0D0000ZZZZ", "Abbott Libre 3 0D0000ABCD", "libre3"
            ),
            (
                device(name: "FreeStyle Libre 3", manufacturer: "Abbott", model: nil, local: "0D0000ABCD"),
                "LibreLoopCGMManager", "0D0000ABCD", "Abbott Libre 3 0D0000ABCD", "libre3"
            ),
            // EversenseKit: the name is the product, the versions left out
            (
                device(name: "Eversense E3", manufacturer: "Senseonics", model: nil, firmware: "6.1", software: "1.2"),
                "EversenseCGMManager", nil, "Senseonics Eversense E3", "eversense"
            ),
            // MockKit: the name is the model
            (
                device(name: "MockCGMManager", manufacturer: "LoopKit", model: "MockCGMManager", software: "1.0"),
                "MockCGMManager", nil, "LoopKit MockCGMManager", "simulator"
            )
        ]
        for (hkDevice, plugin, sensorId, expected, cgmId) in cases {
            let formatted = KnownPlugins.nightscoutDevice(hkDevice, plugin: plugin, sensorId: sensorId, title: "Title")
            XCTAssertEqual(formatted, expected)
            XCTAssertEqual(NightscoutCGMDevice.parse(formatted)?.cgmId, cgmId, expected)
        }
        // Loop's own format of LibreLoop's and LibreTransmitter's devices, as other uploaders send it
        let loopLibre = device(name: "FreeStyle Libre 3", manufacturer: "Abbott", model: "Libre 3 Plus")
        XCTAssertEqual(
            NightscoutCGMDevice.format(loopLibre, sensorId: "0D0000ABCD", title: nil),
            "Abbott Libre 3 Plus 0D0000ABCD"
        )
        let loopBridge = device(name: "MiaomiaoClient", manufacturer: "bubbledevteam", model: nil)
        XCTAssertEqual(
            NightscoutCGMDevice.format(loopBridge, sensorId: "3MH00ABCDE", title: nil),
            "bubbledevteam MiaomiaoClient 3MH00ABCDE"
        )
    }

    /// A G7 before a sensor pairs ("Unknown"), a sensor id that is a placeholder: no id; without an `HKDevice` (the
    /// AppGroup CGM, Dexcom Share, Nightscout as the CGM): the title (the AppGroup source app); nothing at all: nil.
    func testDeviceStringFallbacks() {
        let unpaired = device(name: "Unknown", manufacturer: "Dexcom", model: "G7")
        XCTAssertEqual(NightscoutCGMDevice.format(unpaired, sensorId: nil, title: nil), "Dexcom G7")
        let noSensor = device(name: "MiaomiaoClient", manufacturer: "Abbott", model: nil)
        XCTAssertEqual(NightscoutCGMDevice.format(noSensor, sensorId: "-", title: nil), "Abbott MiaomiaoClient")
        XCTAssertEqual(NightscoutCGMDevice.format(nil, sensorId: nil, title: "xDrip4iOS"), "xDrip4iOS")
        XCTAssertEqual(NightscoutCGMDevice.parse("xDrip4iOS")?.cgmId, "xdrip")
        XCTAssertEqual(NightscoutCGMDevice.format(nil, sensorId: nil, title: "Glucose Direct"), "Glucose Direct")
        XCTAssertEqual(NightscoutCGMDevice.parse("Glucose Direct")?.cgmId, "glucoseDirect")
        XCTAssertEqual(NightscoutCGMDevice.format(nil, sensorId: "x", title: "Dexcom Share"), "Dexcom Share")
        XCTAssertEqual(
            NightscoutCGMDevice.format(device(name: nil, manufacturer: " ", model: nil), sensorId: nil, title: "Title"),
            "Title"
        )
        XCTAssertNil(NightscoutCGMDevice.format(nil, sensorId: nil, title: nil))
        XCTAssertNil(NightscoutCGMDevice.format(nil, sensorId: nil, title: "  "))
    }

    // MARK: - The parser

    /// Every precedent's string: Loop/iAPS, AAPS's `SourceSensor`, xDrip+'s collection methods, xDrip4iOS's and
    /// Spike's BLE names, the bridges; a Dexcom or a Libre of no known model is the family only; the rest none.
    func testParserOnEveryPrecedent() {
        typealias Expected = (cgmId: String?, family: CGMChoice.Family, sensorId: String?)
        let dexcom = CGMChoice.Family.dexcom
        let libre = CGMChoice.Family.libre
        let other = CGMChoice.Family.other
        let cases: [(String, Expected?)] = [
            // Loop and iAPS
            ("Dexcom G5 Mobile 4XXXXX", ("dexcomG5", dexcom, "4XXXXX")),
            ("Dexcom G6 8XXXXX", ("dexcomG6", dexcom, "8XXXXX")),
            ("Dexcom G7 DXCMab", ("dexcomG7", dexcom, "DXCMab")),
            ("Dexcom ONE+ DX02cd", ("dexcomG7", dexcom, "DX02cd")),
            ("Dexcom Stelo DX01ef", ("dexcomG7", dexcom, "DX01ef")),
            ("Dexcom ONE 8YYYYY", ("dexcomG6", dexcom, "8YYYYY")),
            ("Abbott Libre 3 0D0000ABCD", ("libre3", libre, "0D0000ABCD")),
            ("Abbott Libre 3 Plus 0D0000ABCD", ("libre3", libre, "0D0000ABCD")),
            ("Abbott FreeStyle Libre 3 0D0000ABCD", ("libre3", libre, "0D0000ABCD")),
            ("Abbott MiaomiaoClient 3MH00ABCDE", ("libreTransmitter", libre, "3MH00ABCDE")),
            ("Tomato MiaomiaoClient", ("libreTransmitter", libre, nil)),
            ("Abbott LibreTransmitter 3MH00ABCDE", ("libreTransmitter", libre, "3MH00ABCDE")),
            ("Abbott LibreTransmitter", ("libreTransmitter", libre, nil)),
            ("Senseonics Eversense E3", ("eversense", other, nil)),
            ("Medtronic 722 Minimed500", ("enlite", other, nil)),
            ("LoopKit MockCGMManager", ("simulator", other, nil)),
            ("xDrip4iOS", ("xdrip", other, nil)),
            ("Glucose Direct", ("glucoseDirect", other, nil)),
            ("Dexcom Share", (nil, dexcom, nil)),
            ("loop://iPhone", nil),
            // AAPS
            ("G6 Native", ("dexcomG6", dexcom, nil)),
            ("G5 Native", ("dexcomG5", dexcom, nil)),
            ("G6 Native / G5 Native", (nil, dexcom, nil)),
            ("G7", ("dexcomG7", dexcom, nil)),
            ("Dexcom G6", ("dexcomG6", dexcom, nil)),
            ("Dexcom G7", ("dexcomG7", dexcom, nil)),
            ("DexcomG5", (nil, dexcom, nil)),
            ("Dexcom G5 xDrip", (nil, dexcom, nil)),
            ("Dexcom G7 xDrip", ("dexcomG7", dexcom, nil)),
            ("Dexcom Native Unknown", (nil, dexcom, nil)),
            ("Libre2", ("libreTransmitter", libre, nil)),
            ("Libre3", ("libre3", libre, nil)),
            ("Blucon", ("libreTransmitter", libre, nil)),
            ("LimiTTer", ("libreTransmitter", libre, nil)),
            ("Network libre", ("libreTransmitter", libre, nil)),
            ("Eversense", ("eversense", other, nil)),
            ("MM600Series", ("enlite", other, nil)),
            ("Random", nil),
            ("Medtrum A6", nil),
            ("Bluetooth Wixel", nil),
            // xDrip+
            ("xDrip-DexcomG5", (nil, dexcom, nil)),
            ("xDrip-DexcomG5 G6 Native", ("dexcomG6", dexcom, nil)),
            ("xDrip-DexcomG5 G7", ("dexcomG7", dexcom, nil)),
            ("xDrip-DexcomShare", (nil, dexcom, nil)),
            ("xDrip-LibreReceiver", (nil, libre, nil)),
            ("xDrip-LibreReceiver Libre3", ("libre3", libre, nil)),
            ("xDrip-LimiTTer", ("libreTransmitter", libre, nil)),
            ("xDrip-NSFollow", nil),
            ("xDrip-BluetoothWixel", nil),
            ("xDrip-Medtrum", nil),
            // xDrip4iOS and Spike: the BLE name
            ("DexcomAB", (nil, dexcom, "DexcomAB")),
            ("DXCMab", ("dexcomG7", dexcom, "DXCMab")),
            ("MIAOMIAO1234", ("libreTransmitter", libre, "MIAOMIAO1234")),
            ("Bubble", ("libreTransmitter", libre, nil)),
            // the bridges
            ("share2", (nil, dexcom, nil)),
            ("nightscout-librelink-up", (nil, libre, nil)),
            ("freestyle-libre", (nil, libre, nil)),
            // nothing
            ("", nil),
            ("unknown", nil),
            ("Trio", nil)
        ]
        for (text, expected) in cases {
            let parsed = NightscoutCGMDevice.parse(text)
            XCTAssertEqual(parsed?.cgmId, expected?.cgmId, text)
            XCTAssertEqual(parsed?.family, expected?.family, text)
            XCTAssertEqual(parsed?.sensorId, expected?.sensorId, text)
            XCTAssertEqual(parsed == nil, expected == nil, text)
        }
        XCTAssertNil(NightscoutCGMDevice.parse(nil))
    }

    // MARK: - The re-upload of the stored readings

    /// A stored CGM reading is re-uploaded with its recorded session's device; a manual BG, or a reading no session
    /// covers, without one.
    func testTheReUploadTakesTheCoveringSessionsDevice() throws {
        let sessions = [
            session(0, 100, .recorded, device: "Dexcom G6 8AAAAA"),
            session(100, nil, .recorded, device: "Dexcom G6 8BBBBB")
        ]
        XCTAssertEqual(CGMSessionAttribution.device(at: at(50), sessions), "Dexcom G6 8AAAAA")
        XCTAssertEqual(CGMSessionAttribution.device(at: at(100), sessions), "Dexcom G6 8BBBBB")
        XCTAssertNil(CGMSessionAttribution.device(at: at(-1), sessions))

        let reading = ReadingsSnapshot(id: UUID().uuidString, date: at(50), direction: nil, glucose: 120, type: nil)
        let device = CGMSessionAttribution.device(at: at(50), sessions)
        let glucose = try XCTUnwrap(NightscoutConfig.StateModel.glucoseUpload(reading, device: device))
        XCTAssertEqual(glucose.device, "Dexcom G6 8AAAAA")
        XCTAssertEqual(glucose.toNightscoutEntry?.device, "Dexcom G6 8AAAAA")
        XCTAssertNil(NightscoutConfig.StateModel.glucoseUpload(reading)?.device)

        let manual = ReadingsSnapshot(
            id: UUID().uuidString,
            date: at(50),
            direction: nil,
            glucose: 120,
            type: GlucoseType.manual.rawValue
        )
        XCTAssertNil(NightscoutConfig.StateModel.glucoseUpload(manual, device: device)?.device)
    }

    private actor UploadRecorder {
        var upserts: [[BloodGlucose]] = []
        func add(_ records: [BloodGlucose]) { upserts.append(records) }
    }

    private struct RecordingSink: SyncSink {
        let recorder: UploadRecorder
        func upsert(_ items: [SyncUpsert<BloodGlucose>]) async throws {
            await recorder.add(items.map(\.record))
        }

        func delete(_: [BloodGlucose]) async throws {}
    }

    /// The sync signature has no device: a reading uploaded before it had one isn't uploaded again with it.
    func testANewDeviceOnAnUploadedReadingDoesNotUploadItAgain() async {
        let storage = BaseFileStorage()
        let file = "test-cgm-device-\(UUID().uuidString).json"
        defer { Task { await storage.remove(file) } }
        let recorder = UploadRecorder()
        let sync = DataSynchronizer(
            name: "glucose",
            sink: RecordingSink(recorder: recorder),
            storage: storage,
            snapshotFile: file,
            retention: .hours(24),
            deletionWindow: 0
        )
        let date = Date().addingTimeInterval(-.minutes(10)).truncatedToSecond
        let without = BloodGlucose(
            glucose: 120,
            date: Decimal(date.timeIntervalSince1970 * 1000),
            dateString: date,
            type: "sgv"
        )
        var named = without
        named.device = "Dexcom G6 8AAAAA"
        let withDevice = named
        XCTAssertEqual(without.syncID, withDevice.syncID)
        XCTAssertEqual(without.syncSignature, withDevice.syncSignature)

        let first = await sync.reconcile { [without] }
        XCTAssertEqual(first, .synced)
        let again = await sync.reconcile { [withDevice] }
        XCTAssertEqual(again, .noChanges)
        let upserts = await recorder.upserts
        XCTAssertEqual(upserts.count, 1)
        XCTAssertEqual(upserts.first?.map(\.device), [nil])
    }

    // MARK: - The sessions

    /// A changed transmitter or sensor id and a changed CGM each start a new sensor; each session reaches the slack
    /// beyond its entries; the fields come from the CGM's choice (name, plugin, life) and the entries (id, device).
    func testGroupingByIdAndByCGM() {
        let all = entries("Dexcom G6 8AAAAA", 0, 1000) + entries("Dexcom G6 8BBBBB", 1100, 2000) +
            entries("Abbott Libre 3 0D0000ABCD", 2100, 3000, every: 1)
        let sessions = NightscoutCGMSessions.sessions(
            entries: all.shuffled(),
            sensorStarts: [],
            stored: [],
            unknownTimes: all.map(\.date),
            window: DateInterval(start: at(-100), end: at(4000))
        )
        XCTAssertEqual(sessions.map(\.cgmId), ["dexcomG6", "dexcomG6", "libre3"])
        XCTAssertEqual(sessions.map(\.sensorId), ["8AAAAA", "8BBBBB", "0D0000ABCD"])
        XCTAssertEqual(spans(sessions), [[at(-2), at(1002)], [at(1098), at(2002)], [at(2098), at(3002)]])
        XCTAssertEqual(sessions.map(\.sensorStart), [nil, nil, nil])
        XCTAssertEqual(sessions.map(\.source), [.backfilled, .backfilled, .backfilled])
        XCTAssertEqual(sessions.map(\.plugin), ["DexG6Transmitter", "DexG6Transmitter", "LibreLoopCGMManager"])
        XCTAssertEqual(sessions.map(\.name), ["Dexcom G6", "Dexcom G6", "FreeStyle Libre 3 / 3+"])
        XCTAssertEqual(sessions.map(\.oneMinute), [false, false, true])
        XCTAssertEqual(sessions.map(\.device), ["Dexcom G6 8AAAAA", "Dexcom G6 8BBBBB", "Abbott Libre 3 0D0000ABCD"])
        XCTAssertEqual(sessions.first?.expectedLife, .days(10))
    }

    /// A Sensor Start between two entries starts a new sensor there (the session begins at it); the first sensor's
    /// start is the one before its first entry, within its life; a long gap starts another session of the same sensor;
    /// "share2" is the recorded Dexcom; entries naming no CGM are left out.
    func testGroupingByTreatmentAndGapWithAFamilyOnlyDevice() {
        let recorded = CGMSessionRecord(
            id: UUID(),
            start: at(5000),
            snapshot("dexcomG7", plugin: "G7CGMManager", name: "Dexcom G7")
        )
        let all = entries("share2", 0, 1000) + entries("loop://iPhone", 1010, 1090) + entries("share2", 1200, 2000) +
            entries("share2", 2400, 3000)
        let unknown = all.map(\.date)
        let window = DateInterval(start: at(-100), end: at(4000))
        let sessions = NightscoutCGMSessions.sessions(
            entries: all,
            sensorStarts: [at(-20000), at(-500), at(1100), at(1100)],
            stored: [recorded],
            unknownTimes: unknown,
            window: window
        )
        XCTAssertEqual(sessions.map(\.cgmId), ["dexcomG7", "dexcomG7", "dexcomG7"])
        XCTAssertEqual(sessions.map(\.sensorStart), [at(-500), at(1100), at(1100)])
        XCTAssertEqual(spans(sessions), [[at(-2), at(1002)], [at(1100), at(2002)], [at(2398), at(3002)]])

        // no recorded Dexcom: "share2" names none
        XCTAssertEqual(
            NightscoutCGMSessions.sessions(
                entries: all,
                sensorStarts: [],
                stored: [],
                unknownTimes: unknown,
                window: window
            ),
            []
        )
    }

    /// Recorded > entered > backfilled: the backfilled sessions are clipped to the time neither covers and to the
    /// window, and a part without an Unknown reading is dropped; read back, an entered session over a backfilled one
    /// wins whole.
    func testPriorityClipping() {
        let stored = [session(400, 600, .recorded), session(700, 800, .entered, cgmId: "libre3")]
        let all = entries("Dexcom G6 8AAAAA", 0, 1000)
        let unknown = all.map(\.date).filter { ($0 >= at(600) && $0 < at(700)) || $0 >= at(800) }
        let sessions = NightscoutCGMSessions.sessions(
            entries: all,
            sensorStarts: [],
            stored: stored,
            unknownTimes: unknown,
            window: DateInterval(start: at(-100), end: at(900))
        )
        XCTAssertEqual(spans(sessions), [[at(600), at(700)], [at(800), at(900)]])

        let effective = CGMEnteredSessions.effective([
            session(0, 1000, .backfilled),
            session(500, 800, .entered, cgmId: "libre3"),
            session(400, 600, .recorded)
        ])
        XCTAssertEqual(effective.map(\.source), [.backfilled, .recorded, .entered, .backfilled])
        XCTAssertEqual(spans(effective), [[at(0), at(400)], [at(400), at(600)], [at(600), at(800)], [at(800), at(1000)]])
    }

    // MARK: - The store

    /// A store on its own defaults suite: its backfill windows never touch the app's.
    private func store(_ container: NSPersistentContainer) -> CGMSessionStore {
        CGMSessionStore(
            container: container,
            now: { [t0 = Self.t0] in t0 },
            defaults: UserDefaults(suiteName: "test-cgm-sessions-\(UUID().uuidString)")!
        )
    }

    /// The backfilled sessions are stored as backfilled and clipped by the recorded ones; an answer over them wins and
    /// clearing it shows them again; a re-run replaces their time in its window only; the Settings wipe removes them.
    /// A recorded session keeps its device.
    func testStoringBackfilledSessions() async {
        let s = store(StatsFixtures.inMemoryContainer())
        let g6 = snapshot("dexcomG6", plugin: "DexG6Transmitter", name: "Dexcom G6", device: "Dexcom G6 8AAAAA")
        await s.apply(CGMSessionEvent(kind: .manager, cgm: g6, at: at(2000), lastReadingAt: nil))
        await s.storeBackfilled(
            [session(0, 1000, .entered), session(1500, 2500, .recorded)],
            replacing: DateInterval(start: at(-100), end: at(3000))
        )
        var sessions = await s.sessions(in: Self.all)
        XCTAssertEqual(spans(sessions), [[at(0), at(1000)], [at(1500), at(2000)], [at(2000), nil]])
        XCTAssertEqual(sessions.map(\.source), [.backfilled, .backfilled, .recorded])
        XCTAssertEqual(sessions.last?.device, "Dexcom G6 8AAAAA")

        await s.enter([session(300, 500, .entered, cgmId: "libre3")])
        sessions = await s.sessions(in: Self.all)
        XCTAssertEqual(spans(sessions).prefix(3), [[at(0), at(300)], [at(300), at(500)], [at(500), at(1000)]])
        XCTAssertEqual(sessions.map(\.source).prefix(3), [.backfilled, .entered, .backfilled])

        await s.removeAllEntered()
        await s.storeBackfilled([session(200, 400, .backfilled)], replacing: DateInterval(start: at(100), end: at(600)))
        sessions = await s.sessions(in: Self.all)
        XCTAssertEqual(
            spans(sessions),
            [[at(0), at(100)], [at(200), at(400)], [at(600), at(1000)], [at(1500), at(2000)], [at(2000), nil]]
        )

        await s.wipe()
        sessions = await s.sessions(in: Self.all)
        XCTAssertEqual(sessions.map(\.source), [.recorded])
    }

    /// A session's device is updated in place when the CGM's changes (a sensor of the same CGM keeps its row).
    func testTheRulesMergeTheDevice() {
        let open = session(0, nil, .recorded, device: nil)
        var cgm = snapshot("dexcomG6", plugin: "DexG6Transmitter", name: "Dexcom G6", device: "Dexcom G6 8AAAAA")
        let writes = CGMSessionRules.changes(for: cgm, sessions: [open], now: at(10), newID: UUID())
        XCTAssertEqual(writes.map(\.id), [open.id])
        XCTAssertEqual(writes.first?.device, "Dexcom G6 8AAAAA")
        cgm.device = nil
        XCTAssertEqual(CGMSessionRules.merged(writes[0], cgm).device, "Dexcom G6 8AAAAA")
    }

    // MARK: - The CGM topic

    /// The readings Nightscout named count with their CGM; the Unknown card says how many, a Sensors row is "From
    /// Nightscout", its start unknown without a Sensor Start.
    @MainActor func testTheTopicShowsWhatNightscoutNamed() {
        let now = at(7 * 1440)
        let window = DateInterval(start: at(0), end: now)
        let points = stride(from: 0.0, to: 2000, by: 5).map { GlucosePoint(time: at($0), mgdl: 120) }
        let result = Stat.Provider.cgmResult(
            readings: points,
            sessions: CGMEnteredSessions.effective([session(0, 1000, .backfilled)]),
            period: .days7,
            window: window,
            generation: 0,
            now: now,
            calendar: StatsFixtures.berlin
        )
        XCTAssertEqual(result.backfilledReadings, 200)
        XCTAssertEqual(result.cgms.map(\.pick), [.cgm("dexcomG6"), .unknown])
        let sensor = result.picks[.cgm("dexcomG6")]?.sensors.first
        XCTAssertEqual(sensor?.isBackfilled, true)
        let row = sensor.map { Stat.CGMReport.sensorRow($0, now: now, units: .mgdL) }
        XCTAssertEqual(row?.isBackfilled, true)
        XCTAssertEqual(row?.isEntered, false)
        let report = Stat.CGMReport(result, pick: .unknown, units: .mgdL, smoothing: .none)
        XCTAssertTrue(report.unknown?.body.contains("Nightscout named the CGM of 200 more readings") ?? false)

        // the offer: only with Nightscout configured, for Unknown readings outside every window the backfill ran over
        func offers(_ windows: [DateInterval]?) -> Bool {
            let none = Stat.Provider.cgmResult(
                readings: points,
                sessions: [],
                period: .days7,
                window: window,
                generation: 0,
                backfillWindows: windows,
                now: now,
                calendar: StatsFixtures.berlin
            )
            XCTAssertEqual(none.backfilledReadings, 0)
            let unnamed = Stat.CGMReport(none, pick: .unknown, units: .mgdL, smoothing: .none)
            let offered = unnamed.unknown?.body.contains("Backfilling glucose from Nightscout") ?? false
            XCTAssertEqual(offered, none.backfillCanName)
            return offered
        }
        XCTAssertTrue(offers([]))
        XCTAssertTrue(offers([DateInterval(start: at(0), end: at(1000))]))
        XCTAssertFalse(offers(nil))
        XCTAssertFalse(offers([DateInterval(start: at(-10), end: at(3000))]))
        XCTAssertFalse(report.unknown?.body.contains("Backfilling glucose") ?? true)
    }

    // MARK: - One string for a sensor

    /// A reading takes its open session's device once that holds the sensor's id, unless its own device names
    /// another sensor (a batch with the previous sensor's readings after a new pairing); without a session's, its own.
    func testTheLiveDeviceIsTheSessionsOnceItHoldsTheId() {
        XCTAssertTrue(NightscoutCGMDevice.hasID("Dexcom G6 8AAAAA", sensorId: nil))
        XCTAssertTrue(NightscoutCGMDevice.hasID("Abbott LibreTransmitter 3MH00ABCDE", sensorId: nil))
        XCTAssertTrue(NightscoutCGMDevice.hasID("Medtronic 722 Minimed500", sensorId: "Minimed500"))
        XCTAssertFalse(NightscoutCGMDevice.hasID("Abbott LibreTransmitter", sensorId: "3MH00ABCDE"))
        XCTAssertFalse(NightscoutCGMDevice.hasID("Senseonics Eversense E3", sensorId: nil))
        XCTAssertFalse(NightscoutCGMDevice.hasID(nil, sensorId: "3MH00ABCDE"))

        let session = "Abbott LibreTransmitter 3MH00ABCDE"
        XCTAssertEqual(NightscoutCGMDevice.live("Abbott LibreTransmitter", ownDevice: true, session: session), session)
        XCTAssertEqual(NightscoutCGMDevice.live("Tomato MiaomiaoClient", ownDevice: true, session: session), session)
        XCTAssertEqual(NightscoutCGMDevice.live(nil, ownDevice: false, session: session), session)
        XCTAssertEqual(NightscoutCGMDevice.live("Dexcom G6 8AAAAA", ownDevice: true, session: nil), "Dexcom G6 8AAAAA")
        // a new G7 paired: the batch's readings of the previous sensor keep their own device
        let newSensor = "Dexcom G7 DXCMnew"
        let old = "Dexcom G7 DXCMold"
        XCTAssertEqual(NightscoutCGMDevice.live(old, ownDevice: true, session: newSensor), old)
        XCTAssertEqual(NightscoutCGMDevice.live("Dexcom G7 DXCMnew", ownDevice: true, session: newSensor), newSensor)
        // no device of its own: the manager's says nothing of that reading's sensor
        XCTAssertEqual(NightscoutCGMDevice.live("Dexcom G7 DXCMold", ownDevice: false, session: newSensor), newSensor)
    }

    /// A session's device is kept once it holds the sensor's id; nil or an id-less one is replaced.
    func testTheRulesKeepADeviceWithTheSensorsId() {
        var open = session(0, nil, .recorded, device: "Abbott LibreTransmitter")
        open.plugin = "LibreTransmitterManagerV3"
        open.cgmId = "libreTransmitter"
        var cgm = CGMSnapshot(
            plugin: "LibreTransmitterManagerV3",
            cgmId: "libreTransmitter",
            name: "Libre",
            sensorStart: nil,
            expectedLife: nil,
            oneMinute: false,
            sensorId: "3MH00ABCDE",
            device: "Abbott LibreTransmitter 3MH00ABCDE"
        )
        let withID = CGMSessionRules.merged(open, cgm)
        XCTAssertEqual(withID.device, "Abbott LibreTransmitter 3MH00ABCDE")
        cgm.device = "Tomato MiaomiaoClient 3MH00ABCDE"
        XCTAssertEqual(CGMSessionRules.merged(withID, cgm).device, "Abbott LibreTransmitter 3MH00ABCDE")
        cgm.device = nil
        XCTAssertEqual(CGMSessionRules.merged(withID, cgm).device, "Abbott LibreTransmitter 3MH00ABCDE")
    }

    /// The store tells the CGM path the open recorded session's device, for that session's plugin only and once it
    /// holds an id; none after the CGM is removed.
    func testTheStoreTellsTheOpenSessionsDevice() async {
        let s = store(StatsFixtures.inMemoryContainer())
        XCTAssertNil(s.currentDevice(plugin: "DexG6Transmitter"))
        let g6 = snapshot("dexcomG6", plugin: "DexG6Transmitter", name: "Dexcom G6", device: "Dexcom G6 8AAAAA")
        await s.apply(CGMSessionEvent(kind: .manager, cgm: g6, at: at(0), lastReadingAt: nil))
        XCTAssertEqual(s.currentDevice(plugin: "DexG6Transmitter"), "Dexcom G6 8AAAAA")
        XCTAssertNil(s.currentDevice(plugin: "G7CGMManager"))
        await s.apply(CGMSessionEvent(kind: .manager, cgm: nil, at: at(10), lastReadingAt: nil))
        XCTAssertNil(s.currentDevice(plugin: "DexG6Transmitter"))

        let eversense = snapshot(
            "eversense",
            plugin: "EversenseCGMManager",
            name: "Eversense",
            device: "Senseonics Eversense E3"
        )
        await s.apply(CGMSessionEvent(kind: .manager, cgm: eversense, at: at(20), lastReadingAt: nil))
        XCTAssertNil(s.currentDevice(plugin: "EversenseCGMManager"))
    }

    // MARK: - The backfill's other rules

    /// A family-only device ("share2") is the recorded model of the family nearest in time; with two recorded Dexcom
    /// models, none beyond 30 days of either.
    func testAFamilyOnlyDeviceIsTheNearestRecordedModel() {
        let day = 1440.0
        let g6 = session(-200 * day, -170 * day, .recorded)
        let g7 = CGMSessionRecord(
            id: UUID(),
            start: at(10 * day),
            snapshot("dexcomG7", plugin: "G7CGMManager", name: "Dexcom G7")
        )
        let all = entries("share2", -165 * day, -165 * day + 600) + entries("share2", -80 * day, -80 * day + 600) +
            entries("share2", 5 * day, 5 * day + 600)
        let window = DateInterval(start: at(-170 * day), end: at(9 * day))
        let sessions = NightscoutCGMSessions.sessions(
            entries: all,
            sensorStarts: [],
            stored: [g6, g7],
            unknownTimes: all.map(\.date),
            window: window
        )
        XCTAssertEqual(sessions.map(\.cgmId), ["dexcomG6", "dexcomG7"])
        XCTAssertEqual(sessions.map(\.start), [at(-165 * day - 2), at(5 * day - 2)])

        // one recorded model: it, however far
        let onlyG7 = NightscoutCGMSessions.sessions(
            entries: all,
            sensorStarts: [],
            stored: [g7],
            unknownTimes: all.map(\.date),
            window: window
        )
        XCTAssertEqual(onlyG7.map(\.cgmId), ["dexcomG7", "dexcomG7", "dexcomG7"])
    }

    /// A transmitter's id outlives its sensors: a run of one id longer than the G6's 10 days and the grace is split at
    /// its largest gap, again while a part is too long; the later parts' starts unknown.
    func testARunOfOneTransmitterIdIsSplitAtItsLargestGaps() {
        let day = 1440.0
        let all = entries("Dexcom G6 8AAAAA", 0, 10 * day, every: 30) +
            entries("Dexcom G6 8AAAAA", 10 * day + 180, 20 * day, every: 30) +
            entries("Dexcom G6 8AAAAA", 20 * day + 120, 25 * day, every: 30)
        let sessions = NightscoutCGMSessions.sessions(
            entries: all,
            sensorStarts: [at(-60)],
            stored: [],
            unknownTimes: all.map(\.date),
            window: DateInterval(start: at(-100), end: at(26 * day))
        )
        XCTAssertEqual(
            spans(sessions),
            [[at(-2), at(10 * day + 2)], [at(10 * day + 178), at(20 * day + 2)], [at(20 * day + 118), at(25 * day + 2)]]
        )
        XCTAssertEqual(sessions.map(\.sensorStart), [at(-60), nil, nil])
        XCTAssertEqual(sessions.map(\.sensorId), ["8AAAAA", "8AAAAA", "8AAAAA"])
    }

    /// A re-run writes the same ids: they come from the CGM and the start, the kept parts' too; the windows the
    /// backfill ran over are noted, merged, and the wipe forgets them.
    func testBackfilledIdsAreStableAndTheWindowsNoted() async {
        let s = store(StatsFixtures.inMemoryContainer())
        let window = DateInterval(start: at(-100), end: at(2000))
        await s.storeBackfilled([session(0, 1000, .backfilled)], replacing: window)
        let first = await s.sessions(in: Self.all).map(\.id)
        await s.storeBackfilled([session(0, 1000, .backfilled)], replacing: window)
        let again = await s.sessions(in: Self.all).map(\.id)
        XCTAssertEqual(first, again)
        XCTAssertEqual(first, [CGMSessionStore.backfilledID(cgmId: "dexcomG6", start: at(0))])
        await s.storeBackfilled([], replacing: DateInterval(start: at(500), end: at(2500)))
        let kept = await s.sessions(in: Self.all)
        XCTAssertEqual(spans(kept), [[at(0), at(500)]])
        XCTAssertEqual(kept.map(\.id), first)

        await s.storeBackfilled([], replacing: DateInterval(start: at(3000), end: at(4000)))
        var windows = await s.backfillWindows()
        XCTAssertEqual(
            windows,
            [DateInterval(start: at(-100), end: at(2500)), DateInterval(start: at(3000), end: at(4000))]
        )
        await s.wipe()
        windows = await s.backfillWindows()
        XCTAssertEqual(windows, [])
    }

    // MARK: - The backfill's requests

    /// What the stub server saw and answers.
    private final class StubServer: @unchecked Sendable {
        static let host = "ns.invalid"
        static let shared = StubServer()

        private let lock = NSLock()
        private var seen: [URLRequest] = []
        private var entriesServed = false
        /// the entries the first entries page returns (later pages: none)
        var entries: [[String: Any]] = []

        var requests: [URLRequest] {
            lock.withLock { seen }
        }

        func reset(entries: [[String: Any]]) {
            lock.withLock {
                seen = []
                entriesServed = false
                self.entries = entries
            }
        }

        func answer(_ request: URLRequest) -> Data {
            lock.withLock {
                seen.append(request)
                let path = request.url?.path ?? ""
                if path.hasPrefix("/api/v1/entries"), !entriesServed {
                    entriesServed = true
                    return (try? JSONSerialization.data(withJSONObject: entries)) ?? Data("[]".utf8)
                }
                return Data("[]".utf8)
            }
        }
    }

    /// Answers every request to `StubServer.host`: nothing reaches a network.
    private final class StubProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == StubServer.host
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let data = StubServer.shared.answer(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// The backfill's whole fetch through the app's `NightscoutAPI` against a stub server (never a real one): the
    /// glucose backfill's entry pages, then the Sensor Start and Sensor Change pages. Every request is a GET, and the
    /// fetched entries' device names the Unknown readings' CGM.
    func testTheBackfillOnlyGets() async throws {
        let now = Date().truncatedToSecond
        let times = stride(from: 60.0, through: 600, by: 5).map { now.addingTimeInterval(-.minutes($0)) }
        StubServer.shared.reset(entries: times.map { time in
            [
                "_id": UUID().uuidString,
                "sgv": 120.0,
                "date": time.timeIntervalSince1970 * 1000,
                "type": "sgv",
                "device": "Dexcom G6 8AAAAA"
            ]
        })
        URLProtocol.registerClass(StubProtocol.self)
        defer { URLProtocol.unregisterClass(StubProtocol.self) }
        let api = NightscoutAPI(url: try XCTUnwrap(URL(string: "https://\(StubServer.host)")), secret: "secret-secret")

        let since = now.addingTimeInterval(-.days(1))
        let pages = await BaseNightscoutManager.fetchPages(
            since: since,
            until: now,
            date: { (entry: GlucoseEntry) in entry.date },
            page: { try await api.fetchGlucose(dateInterval: $0) },
            reached: { _ in }
        )
        XCTAssertNil(pages.error)
        let glucose = pages.entries.compactMap { BloodGlucose.from(nightscout: $0) }
        XCTAssertEqual(glucose.count, times.count)
        let window = try XCTUnwrap(NightscoutCGMBackfill.window(from: since, now: now))
        let written = StoredSessions()
        let outcome = await NightscoutCGMBackfill.run(
            entries: glucose.compactMap { reading in
                reading.device.map { NightscoutCGMSessions.Entry(date: reading.dateString, device: $0) }
            },
            window: window,
            readings: times,
            sessions: [],
            source: NightscoutCGMBackfillSource(treatments: { try await api.fetchCGMTreatments($0, dateInterval: $1) }),
            store: { sessions, _ in
                await written.set(sessions)
                return true
            }
        )
        XCTAssertNil(outcome.failure)
        XCTAssertEqual(outcome.unknown, times.count)
        XCTAssertEqual(outcome.named, times.count)
        XCTAssertEqual(outcome.sessions, 1)
        let stored = await written.sessions
        XCTAssertEqual(stored.map(\.cgmId), ["dexcomG6"])

        let requests = StubServer.shared.requests
        XCTAssertFalse(requests.isEmpty)
        XCTAssertEqual(Set(requests.map { $0.httpMethod ?? "GET" }), ["GET"])
        XCTAssertNil(requests.first { $0.httpBody != nil })
        let paths = requests.compactMap { $0.url?.path }
        XCTAssertTrue(paths.contains { $0.hasPrefix("/api/v1/entries") })
        XCTAssertTrue(paths.contains { $0.hasPrefix("/api/v1/treatments") })
        let eventTypes = Set(requests.compactMap { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?
                .first { $0.name == "find[eventType]" }?.value
        })
        XCTAssertEqual(eventTypes, ["Sensor Start", "Sensor Change"])
    }

    /// No Unknown reading in the window: nothing is fetched or written.
    func testNoUnknownReadingsFetchNothing() async {
        let fetches = StoredSessions()
        let outcome = await NightscoutCGMBackfill.run(
            entries: entries("Dexcom G6 8AAAAA", 0, 100),
            window: DateInterval(start: at(0), end: at(200)),
            readings: [at(50)],
            sessions: [session(0, nil, .recorded)],
            source: NightscoutCGMBackfillSource(treatments: { _, _ in
                await fetches.set([])
                return []
            }),
            store: { _, _ in
                await fetches.set([])
                return true
            }
        )
        XCTAssertEqual(outcome, NightscoutCGMBackfillOutcome(unknown: 0))
        let calls = await fetches.calls
        XCTAssertEqual(calls, 0)
    }

    private actor StoredSessions {
        var sessions: [CGMSessionRecord] = []
        var calls = 0
        func set(_ sessions: [CGMSessionRecord]) {
            self.sessions = sessions
            calls += 1
        }
    }
}
