
import Foundation
import LoopKit
import UserNotifications

struct AlertIdentity: Sendable, Hashable {
    let managerIdentifier: String
    let alertIdentifier: String

    /// The `UNNotificationRequest` identifier for this alert
    var notificationIdentifier: String {
        "\(managerIdentifier).\(alertIdentifier)"
    }
}

struct AlertEntry: JSON, Codable, Hashable, Sendable {
    let syncIdentifier: UUID?
    let alertIdentifier: String
    var acknowledgedDate: Date?
    var primitiveInterruptionLevel: Decimal?
    let issuedDate: Date
    var scheduledDate: Date?
    var firedDate: Date?
    var retractedDate: Date?
    let managerIdentifier: String
    let triggerType: Int16
    var triggerInterval: Decimal?
    let contentTitle: String?
    let contentBody: String?
    let acknowledgeButtonLabel: String?
    let backgroundContentTitle: String?
    let backgroundContentBody: String?
    let soundName: String?
    let soundIsVibrate: Bool?
    var notificationScheduled: Bool?
    var notificationErrorMessage: String?
    /// The device's error when it could not be told about an acknowledgement. History only: the record
    /// is acknowledged all the same, so this is never a reason to present or re-send the alert.
    var errorMessage: String?

    static let manual = "iAPS"

    static let minimumRepeatInterval: TimeInterval = 60

    static func == (lhs: AlertEntry, rhs: AlertEntry) -> Bool {
        lhs.storageIdentifier == rhs.storageIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(storageIdentifier)
    }

    init(from alert: LoopKit.Alert, issuedDate: Date = Date()) {
        syncIdentifier = UUID()
        alertIdentifier = alert.identifier.alertIdentifier
        primitiveInterruptionLevel = alert.interruptionLevel.storedValue.decimalValue
        self.issuedDate = issuedDate
        managerIdentifier = alert.identifier.managerIdentifier
        triggerType = alert.trigger.storedType
        triggerInterval = alert.trigger.storedInterval?.decimalValue
        contentTitle = alert.foregroundContent?.title
        contentBody = alert.foregroundContent?.body
        acknowledgeButtonLabel = alert.foregroundContent?.acknowledgeActionButtonLabel
        backgroundContentTitle = alert.backgroundContent.title
        backgroundContentBody = alert.backgroundContent.body
        notificationScheduled = false

        switch alert.sound {
        case .vibrate:
            soundName = nil
            soundIsVibrate = true
        case let .sound(name):
            soundName = name
            soundIsVibrate = false
        case nil:
            soundName = nil
            soundIsVibrate = nil
        }

        switch alert.trigger {
        case .immediate:
            scheduledDate = issuedDate
            firedDate = issuedDate
        case let .delayed(interval):
            scheduledDate = issuedDate.addingTimeInterval(max(0, interval))
            firedDate = interval > 0 ? nil : issuedDate
        case let .repeating(repeatInterval):
            let period = max(repeatInterval, Self.minimumRepeatInterval)
            triggerInterval = Decimal(period)
            scheduledDate = issuedDate.addingTimeInterval(period)
            firedDate = nil
        }
    }

    var identity: AlertIdentity {
        AlertIdentity(managerIdentifier: managerIdentifier, alertIdentifier: alertIdentifier)
    }

    var storageIdentifier: String {
        syncIdentifier?.uuidString ?? "\(managerIdentifier).\(alertIdentifier).\(issuedDate.timeIntervalSince1970)"
    }

    var notificationIdentifier: String {
        identity.notificationIdentifier
    }

    var isPending: Bool {
        syncIdentifier != nil && retractedDate == nil && firedDate == nil && scheduledDate != nil
    }

    var isPresentable: Bool {
        retractedDate == nil && (firedDate != nil || syncIdentifier == nil)
    }

    var isRepeating: Bool {
        triggerType == 2
    }

    /// A repeating alert keeps its system request until the issuer retracts it - acknowledging one
    /// occurrence clears that notification, it does not end the alert - so this deliberately ignores
    /// `acknowledgedDate`. Loop replays acknowledged, unretracted repeating alerts for the same reason.
    var requiresNotificationRequest: Bool {
        isPending || (isRepeating && firedDate != nil && retractedDate == nil)
    }

    /// The trigger's interval as stored. For a repeating alert issued by this build it is already
    /// clamped to `minimumRepeatInterval`; records written before that clamp existed may be shorter,
    /// so callers arming a repeating trigger still clamp on the way out.
    var storedTriggerInterval: TimeInterval? {
        triggerInterval.map(Double.init)
    }

    var hasForegroundContent: Bool {
        contentTitle != nil || contentBody != nil
    }

    var interruptionLevel: Alert.InterruptionLevel {
        primitiveInterruptionLevel
            .map { NSDecimalNumber(decimal: $0) }
            .flatMap(Alert.InterruptionLevel.init(storedValue:)) ?? .timeSensitive
    }

    /// Title and body joined, for the log line the alert would otherwise leave no trace in.
    var summary: String {
        [backgroundContentTitle, backgroundContentBody]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
    }

    private enum CodingKeys: String, CodingKey {
        case syncIdentifier
        case alertIdentifier
        case acknowledgedDate
        case primitiveInterruptionLevel
        case issuedDate
        case scheduledDate
        case firedDate
        case retractedDate
        case managerIdentifier
        case triggerType
        case triggerInterval
        case contentTitle
        case contentBody
        case acknowledgeButtonLabel
        case backgroundContentTitle
        case backgroundContentBody
        case soundName
        case soundIsVibrate
        case notificationScheduled
        case notificationErrorMessage
        case errorMessage
    }
}

//
//  StoredAlert.swift
//  Loop
//
//  Created by Rick Pasetto on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

extension Alert.Trigger {
    enum StorageError: Error {
        case invalidStoredInterval
        case invalidStoredType
    }

    var storedType: Int16 {
        switch self {
        case .immediate: return 0
        case .delayed: return 1
        case .repeating: return 2
        }
    }

    var storedInterval: NSNumber? {
        switch self {
        case .immediate: return nil
        case let .delayed(interval): return NSNumber(value: interval)
        case let .repeating(repeatInterval): return NSNumber(value: repeatInterval)
        }
    }

    init(storedType: Int16, storedInterval: NSNumber?, storageDate: Date? = nil, now: Date = Date()) throws {
        switch storedType {
        case 0: self = .immediate
        case 1:
            if let storedInterval = storedInterval {
                if let storageDate = storageDate, storageDate <= now {
                    let intervalLeft = storedInterval.doubleValue - now.timeIntervalSince(storageDate)
                    if intervalLeft <= 0 {
                        self = .immediate
                    } else {
                        self = .delayed(interval: intervalLeft)
                    }
                } else {
                    self = .delayed(interval: storedInterval.doubleValue)
                }
            } else {
                throw StorageError.invalidStoredInterval
            }
        case 2:
            // Strange case here: if it is a repeating trigger, we can't really play back exactly
            // at the right "remaining time" and then repeat at the original period.  So, I think
            // the best we can do is just use the original trigger
            if let storedInterval = storedInterval {
                self = .repeating(repeatInterval: storedInterval.doubleValue)
            } else {
                throw StorageError.invalidStoredInterval
            }
        default:
            throw StorageError.invalidStoredType
        }
    }
}

extension Alert.InterruptionLevel {
    var storedValue: NSNumber {
        // Since this is arbitrary anyway, might as well make it match iOS's values
        switch self {
        case .active:
            if #available(iOS 15.0, *) {
                return NSNumber(value: UNNotificationInterruptionLevel.active.rawValue)
            } else {
                // https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/active
                return 1
            }
        case .timeSensitive:
            if #available(iOS 15.0, *) {
                return NSNumber(value: UNNotificationInterruptionLevel.timeSensitive.rawValue)
            } else {
                // https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive
                return 2
            }
        case .critical:
            if #available(iOS 15.0, *) {
                return NSNumber(value: UNNotificationInterruptionLevel.critical.rawValue)
            } else {
                // https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/critical
                return 3
            }
        }
    }

    init?(storedValue: NSNumber) {
        switch storedValue {
        case Self.active.storedValue: self = .active
        case Self.timeSensitive.storedValue: self = .timeSensitive
        case Self.critical.storedValue: self = .critical
        default:
            return nil
        }
    }
}
