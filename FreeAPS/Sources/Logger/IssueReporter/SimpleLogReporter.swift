import Foundation
import os.log

final class SimpleLogReporter: IssueReporter {
    func setup() {}

    func setUserIdentifier(_: String?) {}

    func reportNonFatalIssue(withName _: String, attributes _: [String: String]) {}

    func reportNonFatalIssue(withError _: NSError) {}

    /// Formats the line and hands it to `LogFileWriter`; no file-system work happens on the caller.
    func log(_ category: String, _ message: String, file: String, function: String, line: UInt) {
        let now = Date()
        LogFileWriter.shared.append("[\(category)] \(file.file) - \(function) - \(line) - \(message)", at: now)
    }

    static var logFile: String {
        getDocumentsDirectory().appendingPathComponent("logs/log.txt").path
    }

    static var logDir: String {
        getDocumentsDirectory().appendingPathComponent("logs").path
    }

    static var logFilePrev: String {
        getDocumentsDirectory().appendingPathComponent("logs/log_prev.txt").path
    }

    /// Holds the log data for a day whose upload failed or could not be attempted.
    /// Written when an upload is queued and deleted after a successful upload.
    static var logFilePending: String {
        getDocumentsDirectory().appendingPathComponent("logs/log_pending.txt").path
    }

    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
}

/// The single writer of `logs/log.txt` (and of the rename to `log_prev.txt`).
///
/// Callers only append to an in-memory buffer under a short lock and never touch the file
/// system: one serial `.utility` queue drains everything pending into one `write(2)` on a
/// kept-open `O_APPEND` descriptor. The line's timestamp is the caller's. The buffer is
/// bounded (`maxPendingBytes`); past it new lines are dropped and counted, and one
/// "dropped N lines" line is written on the next drain. A failed open or write closes the
/// descriptor, counts that batch as dropped and retries on the next drain; the file is
/// never truncated or replaced.
///
/// Rotation is decided per line by the line's own date: when it is on a later day than the
/// open file's `creationDate`, `log.txt` becomes `log_prev.txt` and a new `log.txt` is
/// created with `creationDate` = start of that day. `.logDidRotate` is posted after the
/// rename, from a global queue (observers may log, or even call `error()`).
///
/// Readers in this process call `flush()` / `flushAsync()` first to see every line logged so far.
final class LogFileWriter: @unchecked Sendable {
    static let shared = LogFileWriter(
        directory: SimpleLogReporter.getDocumentsDirectory().appendingPathComponent("logs", isDirectory: true)
    )

    private struct Pending {
        var lines: [(date: Date, text: String)] = []
        var bytes = 0
        var dropped = 0
        var scheduled = false
    }

    private struct OpenFile {
        let fd: Int32
        /// `creationDate` of the open log.txt; a line on a later day rotates it.
        let created: Date
    }

    private static let lineDateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

    private let pending = Protected(Pending())
    private let maxPendingBytes: Int
    private let directory: URL
    private let logFile: URL
    private let logFilePrev: URL
    private let notificationCenter: Foundation.NotificationCenter

    /// The writer queue. Internal (not private) only so tests can hold it to simulate a stalled disk.
    let queue = DispatchQueue(label: "iAPS.LogFileWriter", qos: .utility)
    private let onWriterQueue = DispatchSpecificKey<Bool>()

    // Writer-queue state.
    private var file: OpenFile?
    private var openAttempted = false
    private var buffer: [UInt8] = []
    private var bufferedLines = 0
    private var droppedByWriter = 0
    /// A failed write left an unterminated line at the end of the open file.
    private var partialLine = false
    /// A rotation's rename failed; the file is reopened (and the rotation retried) on the next drain.
    private var rotationPending = false
    private var openFailing = false
    private var formatter = DateFormatter()
    private var formatterLocale: Locale?
    private var formatterTimeZone: TimeZone?

    init(directory: URL, maxPendingBytes: Int = 4 << 20, notificationCenter: Foundation.NotificationCenter = .default) {
        self.directory = directory
        logFile = directory.appendingPathComponent("log.txt")
        logFilePrev = directory.appendingPathComponent("log_prev.txt")
        self.maxPendingBytes = maxPendingBytes
        self.notificationCenter = notificationCenter
        queue.setSpecific(key: onWriterQueue, value: true)
    }

    deinit {
        if let file {
            Darwin.close(file.fd)
        }
    }

    /// Never blocks on I/O: a short lock around an array append, and a `queue.async` for the
    /// first line after a drain.
    func append(_ text: String, at date: Date = Date()) {
        let schedule = pending.write { p -> Bool in
            guard p.bytes < maxPendingBytes else {
                p.dropped += 1
                return false
            }
            p.lines.append((date: date, text: text))
            p.bytes += text.utf8.count
            guard !p.scheduled else { return false }
            p.scheduled = true
            return true
        }
        if schedule {
            queue.async { self.drain() }
        }
    }

    /// Writes everything appended so far, waiting at most `timeout` (a stuck disk must not turn
    /// a crash path or a tap into a hang). Safe from any thread, including the writer queue.
    /// The work item's `wait` raises the writer to the waiter's priority, which a semaphore would not.
    func flush(timeout: DispatchTimeInterval = .seconds(2)) {
        if DispatchQueue.getSpecific(key: onWriterQueue) != nil {
            drain()
            return
        }
        let item = DispatchWorkItem(qos: .userInitiated, flags: .enforceQoS) { self.drain() }
        queue.async(execute: item)
        _ = item.wait(timeout: .now() + timeout)
    }

    /// `flush` for async callers: the bounded wait happens on a dispatch thread, not a cooperative one.
    func flushAsync(timeout: DispatchTimeInterval = .seconds(2)) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                self.flush(timeout: timeout)
                continuation.resume()
            }
        }
    }

    // MARK: - Writer queue

    private func drain() {
        let batch = pending.write { p -> Pending in
            let taken = p
            p = Pending()
            return taken
        }
        let dropped = batch.dropped + droppedByWriter
        droppedByWriter = 0
        guard !batch.lines.isEmpty || dropped > 0 else { return }

        refreshFormatterIfNeeded()
        // Documents is visible in the Files app: if log.txt was deleted or moved under the open
        // descriptor, reopen by path (as the old per-line open did) instead of writing to a lost inode.
        if let file, rotationPending || !isAtLogFilePath(file.fd) {
            closeLogFile()
        }
        openAttempted = false
        for line in batch.lines {
            add(line.text, at: line.date)
        }
        if dropped > 0 {
            add("[Default] LogFileWriter - drain() - 0 - WARN: dropped \(dropped) log lines", at: Date(), isLogLine: false)
            if !commit() {
                droppedByWriter += dropped
            }
        } else {
            commit()
        }
    }

    private func add(_ text: String, at date: Date, isLogLine: Bool = true) {
        let day = Calendar.current.startOfDay(for: date)
        // An open file rotates when the line is on a later day than its creationDate (the same test
        // as before: creationDate < startOfDay). A closed one is (re)opened once per drain.
        let needsOpen = file.map { $0.created < day } ?? !openAttempted
        if needsOpen {
            commit()
            openAttempted = true
            openLogFile(for: day)
        }
        buffer.append(contentsOf: "\(formatter.string(from: date)) \(text)\n".utf8)
        if isLogLine {
            bufferedLines += 1
        }
    }

    /// Writes the buffer to the open file. On failure the descriptor is closed (reopened on the
    /// next drain) and the buffered lines are counted as dropped.
    @discardableResult private func commit() -> Bool {
        defer {
            buffer = []
            bufferedLines = 0
        }
        guard !buffer.isEmpty else { return true }
        if let file {
            if partialLine {
                // Terminate the fragment a failed write left, so it doesn't glue onto this batch's first line.
                buffer.insert(UInt8(ascii: "\n"), at: 0)
            }
            let written = writeAll(buffer, to: file.fd)
            if written == buffer.count {
                partialLine = false
                return true
            }
            if written > 0 {
                partialLine = buffer[written - 1] != UInt8(ascii: "\n")
            }
        }
        closeLogFile()
        droppedByWriter += bufferedLines
        return false
    }

    /// Returns the number of bytes written: all of them unless a write failed.
    private func writeAll(_ bytes: [UInt8], to fd: Int32) -> Int {
        bytes.withUnsafeBytes { raw -> Int in
            guard var pointer = raw.baseAddress else { return 0 }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written > 0 {
                    pointer = pointer.advanced(by: written)
                    remaining -= written
                    continue
                }
                let code = errno
                if written < 0, code == EINTR { continue }
                os_log("LogFileWriter: write failed, errno %d", log: .default, type: .error, code)
                return raw.count - remaining
            }
            return raw.count
        }
    }

    /// Opens log.txt for a line of `day`, first rotating it if it was created before that day.
    /// Leaves `file` nil when it cannot be opened (e.g. before the first unlock after a reboot).
    private func openLogFile(for day: Date) {
        closeLogFile()
        rotationPending = false
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: nil)
        }

        var created = day
        if !fileManager.fileExists(atPath: logFile.path) {
            createLogFile(at: day)
            partialLine = false
        } else if let attributes = try? fileManager.attributesOfItem(atPath: logFile.path),
                  let creationDate = attributes[.creationDate] as? Date
        {
            if creationDate < day {
                try? fileManager.removeItem(at: logFilePrev)
                do {
                    try fileManager.moveItem(at: logFile, to: logFilePrev)
                    createLogFile(at: day)
                    partialLine = false
                    postDidRotate(day: day)
                } catch {
                    // Keep appending to the old file for this drain (`created = day` stops per-line
                    // retries) and retry the rotation on the next one.
                    rotationPending = true
                    os_log("LogFileWriter: rotation failed: %{public}@", log: .default, type: .error, "\(error)")
                }
            } else {
                created = creationDate
            }
        }

        let fd = Darwin.open(logFile.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            let code = errno
            if !openFailing {
                // Logged on the transition only: while the phone is locked after a reboot this fails every drain.
                openFailing = true
                os_log("LogFileWriter: open failed, errno %d", log: .default, type: .error, code)
            }
            return
        }
        if openFailing {
            openFailing = false
            os_log("LogFileWriter: open recovered", log: .default, type: .default)
        }
        file = OpenFile(fd: fd, created: created)
    }

    private func isAtLogFilePath(_ fd: Int32) -> Bool {
        var opened = stat()
        var onDisk = stat()
        guard fstat(fd, &opened) == 0, stat(logFile.path, &onDisk) == 0 else { return false }
        return opened.st_dev == onDisk.st_dev && opened.st_ino == onDisk.st_ino
    }

    private func createLogFile(at date: Date) {
        FileManager.default.createFile(
            atPath: logFile.path,
            contents: nil,
            attributes: [.creationDate: date, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    private func closeLogFile() {
        guard let file else { return }
        Darwin.close(file.fd)
        self.file = nil
    }

    /// Posted from a global queue so observers can log (or call `error()`, which flushes) freely.
    /// log_prev.txt is complete by now: everything before this day was written and the file closed
    /// before the rename.
    private func postDidRotate(day: Date) {
        let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let center = notificationCenter
        DispatchQueue.global(qos: .utility).async {
            center.post(name: .logDidRotate, object: nil, userInfo: ["logDate": prevDate])
        }
    }

    /// A cached formatter built exactly like the old per-line `DateFormatter()`, rebuilt when the
    /// current locale or time zone changes (a cached formatter would not follow them by itself).
    private func refreshFormatterIfNeeded() {
        let locale = Locale.current
        let timeZone = TimeZone.current
        guard locale != formatterLocale || timeZone != formatterTimeZone else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = Self.lineDateFormat
        self.formatter = formatter
        formatterLocale = locale
        formatterTimeZone = timeZone
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}

extension Notification.Name {
    /// Posted after daily log rotation; `userInfo["logDate"]` is the Date the log covers (yesterday).
    static let logDidRotate = Notification.Name("iAPS.logDidRotate")
}
