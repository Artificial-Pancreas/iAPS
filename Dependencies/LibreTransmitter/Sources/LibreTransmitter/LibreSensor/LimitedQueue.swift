//
//  LimitedQueue.swift
//  MiaomiaoClient
//
//  Created by Bjørn Inge Berg on 03/03/2020.
//  Copyright © 2020 Bjørn Inge Vikhammermo Berg. All rights reserved.
//

import Foundation

public struct LimitedQueue<T: Codable>: Codable {
  public var array  = [T]()
  var limit: Int = 10

  mutating func enqueue(_ element: T) {
    while array.count >= limit {
        array.removeFirst()
    }
    array.append(element)
  }

  mutating func dequeue() -> T? {
    array.isEmpty ? nil : array.removeFirst()
  }
}
extension UserDefaults {
    private enum Key: String {
        case queuedSensorData = "no.bjorninge.queuedSensorData"
        case shouldPersistSensorData = "no.bjorninge.shouldPersistSensorData"
    }

    var shouldPersistSensorData: Bool {
        get {
            optionalBool(forKey: Key.shouldPersistSensorData.rawValue) ?? false
        }
        set {
            set(newValue, forKey: Key.shouldPersistSensorData.rawValue)
        }
    }

    public var queuedSensorData: LimitedQueue<SensorData>? {
        get {
            guard let data = object(forKey: Key.queuedSensorData.rawValue) as? Data else {
                return nil
            }

            let decoder = JSONDecoder()
            guard let q = try? decoder.decode(LimitedQueue<SensorData>.self, from: data) else {
                return nil
            }

            return q
        }
        set {
            let encoder = JSONEncoder()
            if let val = newValue, let encoded = try? encoder.encode(val) {
                set(encoded, forKey: Key.queuedSensorData.rawValue)
            } else {
                removeObject(forKey: Key.queuedSensorData.rawValue)
            }
        }
    }
}
