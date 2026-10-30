@testable import FreeAPS
import XCTest

final class LogFileWriterTests: XCTestCase {
    private var directory: URL!

    private var logURL: URL { directory.appendingPathComponent("log.txt") }
    private var prevURL: URL { directory.appendingPathComponent("log_prev.txt") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeWriter(
        maxPendingBytes: Int = 8 << 20,
        center: Foundation.NotificationCenter = Foundation.NotificationCenter(),
        now: @escaping @Sendable() -> Date = { Date() },
        write: @escaping @Sendable(Int32, UnsafeRawPointer, Int) -> Int = { Darwin.write($0, $1, $2) }
    ) -> LogFileWriter {
        LogFileWriter(directory: directory, maxPendingBytes: maxPendingBytes, notificationCenter: center, now: now, write: write)
    }

    /// A fixed local noon in the past, so the drop tests need no wall clock: the marker is dated
    /// `noon + 600` by the injected clock (same day, no rotation), and a directory the test creates
    /// now is never older than the lines.
    private static let noon = Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 5, hour: 12))!
    private static let markerDate = noon.addingTimeInterval(600)

    private func makeDropWriter(
        maxPendingBytes: Int = 8 << 20,
        write: @escaping @Sendable(Int32, UnsafeRawPointer, Int) -> Int = { Darwin.write($0, $1, $2) }
    ) -> LogFileWriter {
        makeWriter(maxPendingBytes: maxPendingBytes, now: { Self.markerDate }, write: write)
    }

    /// The marker line as written, prefix and all.
    private func marker(_ body: String) -> String {
        "\(stamp(Self.markerDate)) [Default] LogFileWriter - drain() - 0 - WARN: \(body)"
    }

    /// Blocks the writer queue (a stalled disk) until the returned semaphore is signalled.
    /// The queue is serial, so everything enqueued after this runs after the release; no need to
    /// wait for the block to start (which would be a priority inversion: main waiting on .utility).
    private func hold(_ writer: LogFileWriter) -> DispatchSemaphore {
        let release = DispatchSemaphore(value: 0)
        writer.queue.async {
            release.wait()
        }
        return release
    }

    func testLineLayoutIsTheOldOne() {
        let writer = makeWriter()
        let date = Date()
        writer.append("[DeviceManager] File.swift - function() - 12 - DEV: message", at: date)
        writer.flush(timeout: .seconds(10))

        // The old SimpleLogReporter built a new formatter like this for every line.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        let expected = "\(formatter.string(from: date)) [DeviceManager] File.swift - function() - 12 - DEV: message\n"
        XCTAssertEqual(try Data(contentsOf: logURL), Data(expected.utf8))
    }

    func testCallersDoNotBlockWhileTheWriterIsStuck() {
        let writer = makeWriter()
        let release = hold(writer)

        let threads = 4
        let perThread = 2500
        let slowest = MaxBox()
        DispatchQueue.concurrentPerform(iterations: threads) { thread in
            for seq in 0 ..< perThread {
                let start = DispatchTime.now().uptimeNanoseconds
                writer.append("T\(thread) \(seq)")
                slowest.record(DispatchTime.now().uptimeNanoseconds - start)
            }
        }
        // A blocking caller would never get here while the queue is held; 500 ms is far above an append.
        XCTAssertLessThan(slowest.value, 500_000_000)
        XCTAssertTrue(readLines(logURL).isEmpty)

        release.signal()
        writer.flush(timeout: .seconds(10))
        XCTAssertEqual(readLines(logURL).count, threads * perThread)
    }

    func testLinesOfEachThreadStayInOrder() {
        let writer = makeWriter()
        let threads = 8
        let perThread = 1000
        DispatchQueue.concurrentPerform(iterations: threads) { thread in
            for seq in 0 ..< perThread {
                writer.append("T\(thread) \(seq)")
            }
        }
        writer.flush(timeout: .seconds(10))

        var last = [Int: Int]()
        var count = 0
        for line in readLines(logURL) {
            let parts = line.split(separator: " ")
            guard parts.count == 3, parts[1].hasPrefix("T"), let thread = Int(parts[1].dropFirst()),
                  let seq = Int(parts[2])
            else {
                XCTFail("unexpected line \(line)")
                continue
            }
            XCTAssertEqual(seq, (last[thread] ?? -1) + 1, "thread \(thread) out of order")
            last[thread] = seq
            count += 1
        }
        XCTAssertEqual(count, threads * perThread)
    }

    func testRotatesByTheLinesOwnDateAndPostsOnceAfterTheRename() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let center = Foundation.NotificationCenter()
        let writer = makeWriter(center: center)

        let rotated = expectation(description: "logDidRotate")
        rotated.assertForOverFulfill = true
        let prevAtNotification = LinesBox()
        let prev = prevURL
        let observer = center.addObserver(forName: .logDidRotate, object: nil, queue: nil) { note in
            XCTAssertEqual(note.userInfo?["logDate"] as? Date, yesterday)
            prevAtNotification.value = readLines(prev)
            rotated.fulfill()
        }
        defer { center.removeObserver(observer) }

        // Logged one second before midnight but written after the next day's first line was logged.
        let release = hold(writer)
        writer.append("old", at: today.addingTimeInterval(-1))
        writer.append("new", at: today.addingTimeInterval(1))
        release.signal()
        writer.flush(timeout: .seconds(10))
        wait(for: [rotated], timeout: 5)

        XCTAssertEqual(prevAtNotification.value.map { $0.hasSuffix(" old") }, [true])
        XCTAssertEqual(readLines(prevURL).map { $0.hasSuffix(" old") }, [true])
        XCTAssertEqual(readLines(logURL).map { $0.hasSuffix(" new") }, [true])
        let created = try FileManager.default.attributesOfItem(atPath: logURL.path)[.creationDate] as? Date
        XCTAssertEqual(created, today)
    }

    func testLogFromAnEarlierDayRotatesOnTheFirstLineAndReplacesTheOldPrev() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        FileManager.default.createFile(atPath: prevURL.path, contents: Data("stale\n".utf8))
        FileManager.default.createFile(
            atPath: logURL.path,
            contents: Data("yesterday\n".utf8),
            attributes: [.creationDate: yesterday]
        )
        let center = Foundation.NotificationCenter()
        let writer = makeWriter(center: center)
        let rotated = expectation(forNotification: .logDidRotate, object: nil, notificationCenter: center)

        writer.append("today")
        writer.flush(timeout: .seconds(10))
        wait(for: [rotated], timeout: 5)

        XCTAssertEqual(readLines(prevURL), ["yesterday"])
        XCTAssertEqual(readLines(logURL).map { $0.hasSuffix(" today") }, [true])
    }

    func testAppendsToTodaysFileWithoutReplacingIt() {
        let today = Calendar.current.startOfDay(for: Date())
        FileManager.default.createFile(atPath: logURL.path, contents: Data("earlier\n".utf8), attributes: [.creationDate: today])
        let writer = makeWriter()

        writer.append("later")
        writer.flush(timeout: .seconds(10))

        let lines = readLines(logURL)
        XCTAssertEqual(lines.first, "earlier")
        XCTAssertEqual(lines.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prevURL.path))
    }

    func testDropsNewLinesPastTheCapAndWritesOneMarker() {
        let writer = makeDropWriter(maxPendingBytes: 1000)
        let release = hold(writer)
        let text = String(repeating: "x", count: 100)
        for i in 0 ..< 100 {
            writer.append(text, at: Self.noon.addingTimeInterval(TimeInterval(i)))
        }
        release.signal()
        writer.flush(timeout: .seconds(10))

        let lines = readLines(logURL)
        XCTAssertEqual(lines.filter { $0.hasSuffix(text) }.count, 10)
        XCTAssertEqual(lines.filter { $0.contains("dropped") }.count, 1)
        // The window starts at the first dropped line (the 11th), not at the drain.
        let since = stamp(Self.noon.addingTimeInterval(10))
        XCTAssertEqual(lines.last, marker("dropped 90 log lines since \(since) (buffer full)"))
    }

    func testFailedOpenDropsTheBatchAndRecoversOnTheNextDrain() throws {
        // A directory where log.txt should be: open(2) fails, and the file must not be replaced.
        try FileManager.default.createDirectory(at: logURL, withIntermediateDirectories: false)
        let writer = makeDropWriter()
        writer.append("lost", at: Self.noon.addingTimeInterval(1))
        writer.flush(timeout: .seconds(10))

        try FileManager.default.removeItem(at: logURL)
        writer.append("kept", at: Self.noon.addingTimeInterval(2))
        writer.flush(timeout: .seconds(10))

        let since = stamp(Self.noon.addingTimeInterval(1))
        XCTAssertEqual(readLines(logURL), [
            "\(stamp(Self.noon.addingTimeInterval(2))) kept",
            marker("dropped 1 log lines since \(since) (open failed: errno 21 EISDIR)")
        ])
    }

    func testFailedWriteDropsTheBatchAndRecoversOnTheNextDrain() {
        let failing = FailingWrites(count: 1, errno: ENOSPC)
        let writer = makeDropWriter(write: { failing.write($0, $1, $2) })
        // The drain scheduled by append fails; the flush's own drain is the next one and writes the marker.
        writer.append("lost", at: Self.noon.addingTimeInterval(1))
        writer.flush(timeout: .seconds(10))

        writer.append("kept", at: Self.noon.addingTimeInterval(2))
        writer.flush(timeout: .seconds(10))

        let since = stamp(Self.noon.addingTimeInterval(1))
        XCTAssertEqual(readLines(logURL), [
            marker("dropped 1 log lines since \(since) (write failed: errno 28 ENOSPC)"),
            "\(stamp(Self.noon.addingTimeInterval(2))) kept"
        ])
    }

    func testMarkerListsEachCauseOfTheWindowInOrder() {
        // The buffer fills while the disk stalls, then the write of what fit fails: the lost
        // marker's window and the failed batch are reported together on the next good drain.
        let failing = FailingWrites(count: 1, errno: ENOSPC)
        let writer = makeDropWriter(maxPendingBytes: 1000, write: { failing.write($0, $1, $2) })
        let release = hold(writer)
        let text = String(repeating: "x", count: 100)
        for i in 0 ..< 15 {
            writer.append(text, at: Self.noon.addingTimeInterval(TimeInterval(i)))
        }
        // The drain scheduled by the first append fails; the flush's own drain writes the marker.
        release.signal()
        writer.flush(timeout: .seconds(10))

        // 10 failed in the write, 5 never fit; the window starts at the first line of the failed batch.
        XCTAssertEqual(readLines(logURL), [
            marker("dropped 15 log lines since \(stamp(Self.noon)) (buffer full, write failed: errno 28 ENOSPC)")
        ])
    }

    func testFlushOnTheWriterQueueDoesNotDeadlock() {
        let writer = makeWriter()
        let log = logURL
        let seen = LinesBox()
        let done = expectation(description: "flushed on the writer queue")
        writer.queue.async {
            writer.append("line")
            writer.flush()
            seen.value = readLines(log)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(seen.value.count, 1)
    }

    func testFlushReturnsAfterTheTimeoutWhenTheWriterIsStuck() {
        let writer = makeWriter()
        let release = hold(writer)
        writer.append("line")

        let start = Date()
        writer.flush(timeout: .milliseconds(200))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0.15)
        XCTAssertLessThan(elapsed, 2)
        XCTAssertTrue(readLines(logURL).isEmpty)

        release.signal()
        writer.flush(timeout: .seconds(10))
        XCTAssertEqual(readLines(logURL).count, 1)
    }
}

/// The line prefix's format.
private func stamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    return formatter.string(from: date)
}

private func readLines(_ url: URL) -> [String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").map(String.init)
}

private final class LinesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: [String] = []

    var value: [String] {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Fails the first `count` write(2) calls with `errno`, then writes for real.
private final class FailingWrites: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private let code: Int32

    init(count: Int, errno code: Int32) {
        remaining = count
        self.code = code
    }

    func write(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {
        let fail = lock.withLock { () -> Bool in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        guard !fail else {
            errno = code
            return -1
        }
        return Darwin.write(fd, bytes, count)
    }
}

private final class MaxBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: UInt64 = 0

    var value: UInt64 { lock.withLock { _value } }

    func record(_ sample: UInt64) {
        lock.withLock { _value = max(_value, sample) }
    }
}
