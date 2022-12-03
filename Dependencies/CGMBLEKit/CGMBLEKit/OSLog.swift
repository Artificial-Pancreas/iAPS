//
//  OSLog.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//
//
//  OSLog.swift
//  OmniBLE
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
// OSLog updated for FreeAPSX logs
//

import os.log
import Foundation


let loggerLock = NSRecursiveLock()
let baseReporter: IssueReporter = SimpleLogReporter()
let category = Logger.Category.CGMBLEKit

extension NSLocking {
    func perform<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}

extension NSRecursiveLock {
    convenience init(label: String) {
        self.init()
        name = label
    }
}

extension NSLock {
    convenience init(label: String) {
        self.init()
        name = label
    }
}

extension OSLog {
    
    convenience init(category: String) {
        self.init(subsystem: "com.loopkit.CGMBLEKit", category: category)
    }

    func debug(_ message: StaticString, _ args: CVarArg...) {
        let msg = message.debugDescription
        DispatchWorkItem(qos: .userInteractive, flags: .enforceQoS) {
            loggerLock.perform {
                category.logger.debug(
                    msg,
                    printToConsole: true,
                    file: #file,
                    function: #function,
                    line: #line
                )
            }
        }.perform()
    }

    func info(_ message: StaticString, _ args: CVarArg...) {
        let msg = message.debugDescription
        DispatchWorkItem(qos: .userInteractive, flags: .enforceQoS) {
            loggerLock.perform {
                category.logger.info(
                    msg,
                    file: #file,
                    function: #function,
                    line: #line
                )
            }
        }.perform()
    }

    func `default`(_ message: StaticString, _ args: CVarArg...) {
        let msg = message.debugDescription
        DispatchWorkItem(qos: .userInteractive, flags: .enforceQoS) {
            loggerLock.perform {
                category.logger.debug(
                    msg,
                    printToConsole: true,
                    file: #file,
                    function: #function,
                    line: #line
                )
            }
        }.perform()
    }

    func error(_ message: StaticString, _ args: CVarArg...) {
        let msg = message.debugDescription
        DispatchWorkItem(qos: .userInteractive, flags: .enforceQoS) {
           
            loggerLock.perform {
                category.logger.warning(
                    msg,
                    description: message.debugDescription,
                    error: nil,
                    file: #file,
                    function: #function,
                    line: #line
                )
            }
        }.perform()
    }

    private func log(_ message: StaticString, type: OSLogType, _ args: [CVarArg]) {
        switch args.count {
        case 0:
            os_log(message, log: self, type: type)
        case 1:
            os_log(message, log: self, type: type, args[0])
        case 2:
            os_log(message, log: self, type: type, args[0], args[1])
        case 3:
            os_log(message, log: self, type: type, args[0], args[1], args[2])
        case 4:
            os_log(message, log: self, type: type, args[0], args[1], args[2], args[3])
        case 5:
            os_log(message, log: self, type: type, args[0], args[1], args[2], args[3], args[4])
        default:
            os_log(message, log: self, type: type, args)
        }
    }
}

protocol IssueReporter: AnyObject {
    /// Call this method in `applicationDidFinishLaunching()`.
    func setup()

    func setUserIdentifier(_: String?)

    func reportNonFatalIssue(withName: String, attributes: [String: String])

    func reportNonFatalIssue(withError: NSError)

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt)
}

final class Logger {
    static let `default` = Logger(category: .default, reporter: baseReporter)
    static let  CGMBLEKit = Logger(category: .CGMBLEKit, reporter: baseReporter)

    enum Category: String {
        case `default`
        case CGMBLEKit

        var name: String {
            rawValue
        }

        var logger: Logger {
            switch self {
            case .default: return .default
            case .CGMBLEKit: return .CGMBLEKit
            
            }
        }

        fileprivate var log: OSLog {
            let subsystem = Bundle.main.bundleIdentifier!
            switch self {
            case .default: return OSLog.default
            case .CGMBLEKit: return OSLog(subsystem: subsystem, category: name)
            }
        }
    }

    fileprivate enum Error: Swift.Error {
        case error(String)
        case errorWithInnerError(String, Swift.Error)
        case errorWithDescription(String, String)
        case errorWithDescriptionAndInnerError(String, String, Swift.Error)

        private func domain() -> String {
            switch self {
            case let .error(domain),
                 let .errorWithDescription(domain, _),
                 let .errorWithDescriptionAndInnerError(domain, _, _),
                 let .errorWithInnerError(domain, _):
                return domain
            }
        }

        private func innerError() -> Swift.Error? {
            switch self {
            case let .errorWithDescriptionAndInnerError(_, _, error),
                 let .errorWithInnerError(_, error):
                return error
            default: return nil
            }
        }

        func asNSError() -> NSError {
            var info: [String: Any] = ["Description": String(describing: self)]

            if let error = innerError() {
                info["Error"] = String(describing: error)
            }

            return NSError(domain: domain(), code: -1, userInfo: info)
        }
    }

    private let category: Category
    private let reporter: IssueReporter
    let log: OSLog

    private init(category: Category, reporter: IssueReporter) {
        self.category = category
        self.reporter = reporter
        log = category.log
    }

    static func setup() {
        loggerLock.perform {
            baseReporter.setup()
        }
    }

    func debug(
        _ message: @autoclosure () -> String,
        printToConsole: Bool = true,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        let message = "DEV: \(message())"
        if printToConsole {
            os_log("%@ - %@ - %d %{public}@", log: log, type: .debug, file.file, function, line, message)
        }
        reporter.log(category.name, message, file: file, function: function, line: line)
    }

    func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        let printedMessage = "INFO: \(message)"
        os_log("%@ - %@ - %d %{public}@", log: log, type: .info, file.file, function, line, printedMessage)
        reporter.log(category.name, printedMessage, file: file, function: function, line: line)
    }

    func warning(
        _ message: String,
        description: String? = nil,
        error maybeError: Swift.Error? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        let loggerError = maybeError.loggerError(message: message, withDescription: description)
        let message = "WARN: \(String(describing: loggerError))"

        os_log("%@ - %@ - %d %{public}@", log: log, type: .default, file.file, function, line, message)
        reporter.log(category.name, message, file: file, function: function, line: line)
        reporter.reportNonFatalIssue(withError: loggerError.asNSError())
        
    }

    func error(
        _ message: String,
        description: String? = nil,
        error maybeError: Swift.Error? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) -> Never {
        errorWithoutFatalError(message, description: description, error: maybeError, file: file, function: function, line: line)

        fatalError(
            "\(message) @ \(String(describing: description)) @ \(String(describing: maybeError)) @ \(file) @ \(function) @ \(line)"
        )
    }


    fileprivate func errorWithoutFatalError(
        _ message: String,
        description: String? = nil,
        error maybeError: Swift.Error? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        let loggerError = maybeError.loggerError(message: message, withDescription: description)
        let message = "ERR: \(String(describing: loggerError))"

        os_log("%@ - %@ - %d %{public}@", log: log, type: .error, file.file, function, line, message)
        reporter.log(category.name, message, file: file, function: function, line: line)
        reporter.reportNonFatalIssue(withError: loggerError.asNSError())
    }
}

private extension Optional where Wrapped == Swift.Error {
    func loggerError(message: String, withDescription description: String?) -> Logger.Error {
        switch (description, self) {
        case (nil, nil):
            return .error(message)
        case let (descr?, nil):
            return .errorWithDescription(message, descr)
        case let (nil, error?):
            return .errorWithInnerError(message, error)
        case let (descr?, error?):
            return .errorWithDescriptionAndInnerError(message, descr, error)
        }
    }
}


final class SimpleLogReporter: IssueReporter {
    private let fileManager = FileManager.default

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }

    func setup() {}

    func setUserIdentifier(_: String?) {}

    func reportNonFatalIssue(withName _: String, attributes _: [String: String]) {}

    func reportNonFatalIssue(withError _: NSError) {}

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt) {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        if !fileManager.fileExists(atPath: SimpleLogReporter.logDir) {
            try? fileManager.createDirectory(
                atPath: SimpleLogReporter.logDir,
                withIntermediateDirectories: false,
                attributes: nil
            )
        }

        if !fileManager.fileExists(atPath: SimpleLogReporter.logFile) {
            createFile(at: startOfDay)
        } else {
            if let attributes = try? fileManager.attributesOfItem(atPath: SimpleLogReporter.logFile),
               let creationDate = attributes[.creationDate] as? Date, creationDate < startOfDay
            {
                try? fileManager.removeItem(atPath: SimpleLogReporter.logFilePrev)
                try? fileManager.moveItem(atPath: SimpleLogReporter.logFile, toPath: SimpleLogReporter.logFilePrev)
                createFile(at: startOfDay)
            }
        }

        let logEntry = "\(dateFormatter.string(from: now)) [\(category)] \(file.file) - \(function) - \(line) - \(message)\n"
        let data = logEntry.data(using: .utf8)!
        try? data.append(fileURL: URL(fileURLWithPath: SimpleLogReporter.logFile))
    }

    private func createFile(at date: Date) {
        fileManager.createFile(atPath: SimpleLogReporter.logFile, contents: nil, attributes: [.creationDate: date])
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

    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
}

private extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: fileURL, options: .atomic)
        }
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}

