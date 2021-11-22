//
//  LogExport.swift
//  LibreTransmitter
//
//  Created by Bjørn Inge Berg on 22/09/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import Foundation
import OSLog


@available(iOS 15, *)
fileprivate func getLogEntries() throws -> [OSLogEntryLog] {
    // Open the log store.
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)

    // Get all the logs from the last hour.
    let oneHourAgo = logStore.position(date: Date().addingTimeInterval(-3600))

    // Fetch log objects.
    let allEntries = try logStore.getEntries(at: oneHourAgo)

    // Filter the log to be relevant for our specific subsystem
    // and remove other elements (signposts, etc).
    return allEntries
        .compactMap { $0 as? OSLogEntryLog }
        //.filter { $0.subsystem == Features.logSubsystem }
}

@available(iOS 15, *)
func getLogAsData() throws -> Data {
    var data = Data()
    let entries = try getLogEntries()
    entries.forEach { log in
        if let logstring = [log.date.ISO8601Format(), log.subsystem, log.category, "[["+log.composedMessage+"]]\r\n"]
            .joined(separator: "||").data(using: .utf8, allowLossyConversion: false) {
            data.append(logstring)
        }

    }
    return data
}

func getLogs() throws -> Data {
    var logs = Data()
    if #available(iOS 15, *) {
        logs = try getLogAsData()
    }
    return logs

}


public extension Logger {
    init(forType atype: Any, forSubSystem subsystem: String=Features.logSubsystem) {
        self.init(subsystem: subsystem, category: String(describing: atype)  )
    }

}
