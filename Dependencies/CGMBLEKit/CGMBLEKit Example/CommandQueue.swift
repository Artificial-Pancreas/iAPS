//
//  CommandQueue.swift
//  CGMBLEKit Example
//
//  Created by Paul Dickens on 25/03/2018.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import CGMBLEKit


class CommandQueue {
    private var list = Array<Command>()
    private var lock = os_unfair_lock()

    func enqueue(_ element: Command) {
        os_unfair_lock_lock(&lock)
        list.append(element)
        os_unfair_lock_unlock(&lock)
    }

    func dequeue() -> Command? {
        os_unfair_lock_lock(&lock)
        defer {
            os_unfair_lock_unlock(&lock)
        }
        if !list.isEmpty {
            return list.removeFirst()
        } else {
            return nil
        }
    }
}
