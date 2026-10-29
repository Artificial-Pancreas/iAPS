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
/// bounded (`maxPendingBytes`); past it new lines are dropped and counted. A failed open or
/// write closes the descriptor, counts that batch as dropped and retries on the next drain;
/// the file is never truncated or replaced. Once a drain can write again, one line
/// "dropped N log lines since <first dropped line's date> (<causes>)" accounts for the gap.
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
        var dropped = DropWindow()
        var scheduled = false
    }

    /// Why lines were dropped.
    private enum DropCause: Equatable {
        case bufferFull
        case openFailed(Int32)
        case writeFailed(Int32)

        var text: String {
            switch self {
            case .bufferFull: return "buffer full"
            case let .openFailed(code): return "open failed: \(Self.describe(code))"
            case let .writeFailed(code): return "write failed: \(Self.describe(code))"
            }
        }

        /// `errno 28 ENOSPC`; just the number for codes not listed.
        private static func describe(_ code: Int32) -> String {
            let name: String
            switch code {
            case EPERM: name = "EPERM"
            case ENOENT: name = "ENOENT"
            case EINTR: name = "EINTR"
            case EIO: name = "EIO"
            case EBADF: name = "EBADF"
            case EACCES: name = "EACCES"
            case ENOTDIR: name = "ENOTDIR"
            case EISDIR: name = "EISDIR"
            case EINVAL: name = "EINVAL"
            case ENFILE: name = "ENFILE"
            case EMFILE: name = "EMFILE"
            case EFBIG: name = "EFBIG"
            case ENOSPC: name = "ENOSPC"
            case EROFS: name = "EROFS"
            case EAGAIN: name = "EAGAIN"
            case EDQUOT: name = "EDQUOT"
            default: return "errno \(code)"
            }
            return "errno \(code) \(name)"
        }
    }

    /// The lines lost since the last marker that made it to the file.
    ///
    /// Several causes in one window are all kept: each distinct cause once, in the order the
    /// writer recorded them.
    private struct DropWindow {
        var count = 0
        /// The caller's timestamp of the earliest dropped line; nil while nothing was dropped.
        var since: Date?
        var causes: [DropCause] = []

        /// No dropped lines (causes alone don't count).
        var isEmpty: Bool { count == 0 }

        mutating func add(_ lines: Int, since date: Date, cause: DropCause? = nil) {
            if let cause {
                note(cause)
            }
            guard lines > 0 else { return }
            count += lines
            since = min(since ?? date, date)
        }

        mutating func add(_ other: DropWindow) {
            if let otherSince = other.since {
                add(other.count, since: otherSince)
            }
            other.causes.forEach { note($0) }
        }

        /// Records a cause without lines: a failed write that held only the marker.
        mutating func note(_ cause: DropCause) {
            if !causes.contains(cause) {
                causes.append(cause)
            }
        }

        /// `WARN: dropped 90 log lines since 2026-10-27T03:12:40+0100 (write failed: errno 28 ENOSPC)`.
        /// The date uses the formatter of the line prefix, so the two compare directly.
        func marker(_ formatter: DateFormatter) -> String {
            var text = "WARN: dropped \(count) log lines"
            if let since {
                text += " since \(formatter.string(from: since))"
            }
            if !causes.isEmpty {
                text += " (\(causes.map(\.text).joined(separator: ", ")))"
            }
            return text
        }
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
    /// The marker line's date. Injectable (as is `write`) only for tests.
    private let now: @Sendable() -> Date
    private let systemWrite: @Sendable(Int32, UnsafeRawPointer, Int) -> Int

    /// The writer queue. Internal (not private) only so tests can hold it to simulate a stalled disk.
    let queue = DispatchQueue(label: "iAPS.LogFileWriter", qos: .utility)
    private let onWriterQueue = DispatchSpecificKey<Bool>()

    // Writer-queue state.
    private var file: OpenFile?
    private var openAttempted = false
    private var buffer: [UInt8] = []
    private var bufferedLines = 0
    /// The earliest date among `bufferedLines`.
    private var bufferedSince: Date?
    private var droppedByWriter = DropWindow()
    /// A failed write left an unterminated line at the end of the open file.
    private var partialLine = false
    /// A rotation's rename failed; the file is reopened (and the rotation retried) on the next drain.
    private var rotationPending = false
    private var openFailing = false
    /// Why `file` is nil: the failed open, or the failed write that closed it.
    private var fileFailure: DropCause?
    private var formatter = DateFormatter()
    private var formatterLocale: Locale?
    private var formatterTimeZone: TimeZone?

    init(
        directory: URL,
        maxPendingBytes: Int = 4 << 20,
        notificationCenter: Foundation.NotificationCenter = .default,
        now: @escaping @Sendable() -> Date = { Date() },
        write: @escaping @Sendable(Int32, UnsafeRawPointer, Int) -> Int = { Darwin.write($0, $1, $2) }
    ) {
        self.directory = directory
        logFile = directory.appendingPathComponent("log.txt")
        logFilePrev = directory.appendingPathComponent("log_prev.txt")
        self.maxPendingBytes = maxPendingBytes
        self.notificationCenter = notificationCenter
        self.now = now
        systemWrite = write
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
                p.dropped.add(1, since: date, cause: .bufferFull)
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
        // Earlier drains' losses happened before this batch's buffer-full drops.
        var dropped = droppedByWriter
        dropped.add(batch.dropped)
        droppedByWriter = DropWindow()
        guard !batch.lines.isEmpty || !dropped.isEmpty else { return }

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
        if !dropped.isEmpty {
            add("[Default] LogFileWriter - drain() - 0 - \(dropped.marker(formatter))", at: now(), isLogLine: false)
            if !commit() {
                // The marker was lost with this batch: carry its window, ahead of this failure.
                dropped.add(droppedByWriter)
                droppedByWriter = dropped
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
            bufferedSince = min(bufferedSince ?? date, date)
        }
    }

    /// Writes the buffer to the open file. On failure the descriptor is closed (reopened on the
    /// next drain) and the buffered lines are counted as dropped.
    @discardableResult private func commit() -> Bool {
        defer {
            buffer = []
            bufferedLines = 0
            bufferedSince = nil
        }
        guard !buffer.isEmpty else { return true }
        if let file {
            if partialLine {
                // Terminate the fragment a failed write left, so it doesn't glue onto this batch's first line.
                buffer.insert(UInt8(ascii: "\n"), at: 0)
            }
            let (written, code) = writeAll(buffer, to: file.fd)
            if written == buffer.count {
                partialLine = false
                return true
            }
            if written > 0 {
                partialLine = buffer[written - 1] != UInt8(ascii: "\n")
            }
            fileFailure = .writeFailed(code)
        }
        closeLogFile()
        // Noted even when only the marker was lost, so a change of cause between drains shows up.
        if let fileFailure {
            droppedByWriter.note(fileFailure)
        }
        if let bufferedSince {
            droppedByWriter.add(bufferedLines, since: bufferedSince)
        }
        return false
    }

    /// Returns the number of bytes written (all of them unless a write failed) and the failed write's errno.
    private func writeAll(_ bytes: [UInt8], to fd: Int32) -> (written: Int, code: Int32) {
        bytes.withUnsafeBytes { raw -> (written: Int, code: Int32) in
            guard var pointer = raw.baseAddress else { return (0, 0) }
            var remaining = raw.count
            while remaining > 0 {
                let written = systemWrite(fd, pointer, remaining)
                if written > 0 {
                    pointer = pointer.advanced(by: written)
                    remaining -= written
                    continue
                }
                // A 0 return sets no errno; report it as EIO rather than whatever errno held.
                let code = written < 0 ? errno : EIO
                if code == EINTR { continue }
                os_log("LogFileWriter: write failed, errno %d", log: .default, type: .error, code)
                return (raw.count - remaining, code)
            }
            return (raw.count, 0)
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
            fileFailure = .openFailed(code)
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
        fileFailure = nil
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
