//
//  OSLog.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 06/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import os.log
import OSLog
import Combine

let formatter = DateFormatter()

var logs: [String] = []
extension OSLog {
    convenience init(category: String) {
        self.init(subsystem: "com.randallknutson.DanaKit", category: category)
    }

    func debug(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .debug, args)
    }

    func info(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .info, args)
    }

    func `default`(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .default, args)
    }

    func error(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .error, args)
    }
    
    func getDebugLogs() -> String {
        do {
            let logStore = try OSLogStore(scope: .currentProcessIdentifier)
            let fiveTeenMinAgo = logStore.position(date: Date().addingTimeInterval(-900))
            let allEntries = try logStore.getEntries(at: fiveTeenMinAgo)
            
            return allEntries
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == "com.randallknutson.DanaKit" }
                .map({ "[\($0.date.formatted(date: .numeric, time: .shortened)) \(getLevel($0.level))] \($0.composedMessage)" })
                .joined(separator: "\n")
        } catch {
            return ""
        }
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
    
    private func getLevel(_ type: OSLogEntryLog.Level) -> String {
        switch type {
        case .info:
            return "INFO"
        case .notice:
            return "DEFAULT"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        case .debug:
            return "DEBUG"
        default:
            return "UNKNOWN"
        }
    }
}
