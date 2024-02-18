//
//  OSLog.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 06/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import OSLog
import Combine

extension Logger {
    init(category: String) {
        self.init(subsystem: "com.randallknutson.DanaKit", category: category)
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
