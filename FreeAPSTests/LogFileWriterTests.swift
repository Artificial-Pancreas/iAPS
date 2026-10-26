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
        center: Foundation.NotificationCenter = Foundation.NotificationCenter()
    ) -> LogFileWriter {
        LogFileWriter(directory: directory, maxPendingBytes: maxPendingBytes, notificationCenter: center)
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
        let writer = makeWriter(maxPendingBytes: 1000)
        let release = hold(writer)
        let text = String(repeating: "x", count: 100)
        for _ in 0 ..< 100 {
            writer.append(text)
        }
        release.signal()
        writer.flush(timeout: .seconds(10))

        let lines = readLines(logURL)
        XCTAssertEqual(lines.filter { $0.hasSuffix(text) }.count, 10)
        XCTAssertEqual(lines.filter { $0.contains("dropped") }.count, 1)
        XCTAssertTrue(lines.last?.hasSuffix("WARN: dropped 90 log lines") ?? false)
    }

    func testFailedOpenDropsTheBatchAndRecoversOnTheNextDrain() throws {
        // A directory where log.txt should be: open(2) fails, and the file must not be replaced.
        try FileManager.default.createDirectory(at: logURL, withIntermediateDirectories: false)
        let writer = makeWriter()
        writer.append("lost")
        writer.flush(timeout: .seconds(10))

        try FileManager.default.removeItem(at: logURL)
        writer.append("kept")
        writer.flush(timeout: .seconds(10))

        let lines = readLines(logURL)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.first?.hasSuffix(" kept") ?? false)
        XCTAssertTrue(lines.last?.hasSuffix("WARN: dropped 1 log lines") ?? false)
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

private final class MaxBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: UInt64 = 0

    var value: UInt64 { lock.withLock { _value } }

    func record(_ sample: UInt64) {
        lock.withLock { _value = max(_value, sample) }
    }
}
