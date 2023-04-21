//
//  PumpOpsSynchronous.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/12/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import RileyLinkBLEKit


public protocol PumpOpsSessionDelegate: AnyObject {
    func pumpOpsSession(_ session: PumpOpsSession, didChange state: PumpState)
    func pumpOpsSessionDidChangeRadioConfig(_ session: PumpOpsSession)
}

public enum SetBolusError: Error {
    case certain(PumpOpsError)
    case uncertain(PumpOpsError)
}

extension SetBolusError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .certain(let error):
            return error.errorDescription
        case .uncertain(let error):
            return String(format: LocalizedString("Bolus may have failed: %1$@", comment: "Format string for uncertain bolus. (1: the reported error during bolusing)"), error.localizedDescription)
        }
    }

    public var recoverySuggestion: String? {
        
        switch self {
        case .certain(let error):
            return error.recoverySuggestion
        case .uncertain:
            return LocalizedString("Please check your pump bolus history to determine if the bolus was delivered.", comment: "recoverySuggestion for uncertain bolus")
        }
    }

    public var helpAnchor: String? {
        switch self {
        case .certain(let error):
            return error.errorDescription
        case .uncertain:
            return LocalizedString("Loop sent a bolus command to the pump, but was unable to confirm that the pump received the command. For safety, Loop will assume the bolus was delivered. When Loop eventually fetches history from the pump, and the estimated bolus finish time is passed, Loop will update its records of delivery to match what the pump reports.", comment: "Help anchor for uncertain bolus")
        }
    }
}


public class PumpOpsSession {

    private(set) public var pump: PumpState {
        didSet {
            delegate.pumpOpsSession(self, didChange: pump)
        }
    }
    public let settings: PumpSettings
    private let messageSender: PumpMessageSender

    private unowned let delegate: PumpOpsSessionDelegate
    
    public init(settings: PumpSettings, pumpState: PumpState, messageSender: PumpMessageSender, delegate: PumpOpsSessionDelegate) {
        self.settings = settings
        self.pump = pumpState
        self.messageSender = messageSender
        self.delegate = delegate
    }
}


// MARK: - Wakeup and power
extension PumpOpsSession {
    private static let minimumTimeBetweenWakeAttempts = TimeInterval(minutes: 1)

    /// Attempts to send initial short wakeup message that kicks off the wakeup process.
    ///
    /// If successful, still does not fully wake up the pump - only alerts it such that the longer wakeup message can be sent next.
    ///
    /// - Throws:
    ///     - PumpCommandError.command containing:
    ///         - PumpOpsError.couldNotDecode
    ///         - PumpOpsError.crosstalk
    ///         - PumpOpsError.deviceError
    ///         - PumpOpsError.noResponse
    ///         - PumpOpsError.unexpectedResponse
    ///         - PumpOpsError.unknownResponse
    private func sendWakeUpBurst() throws {
        // Skip waking up if we recently tried
        guard pump.lastWakeAttempt == nil || pump.lastWakeAttempt!.timeIntervalSinceNow <= -PumpOpsSession.minimumTimeBetweenWakeAttempts
        else {
            return
        }

        pump.lastWakeAttempt = Date()

        let shortPowerMessage = PumpMessage(pumpID: settings.pumpID, type: .powerOn)

        if pump.pumpModel == nil || !pump.pumpModel!.hasMySentry {
            // Older pumps have a longer sleep cycle between wakeups, so send an initial burst
            do {
                let _: PumpAckMessageBody = try messageSender.getResponse(to: shortPowerMessage, responseType: .pumpAck, repeatCount: 255, timeout: .milliseconds(1), retryCount: 0)
            }
            catch { }
        }

        do {
            let _: PumpAckMessageBody = try messageSender.getResponse(to: shortPowerMessage, responseType: .pumpAck, repeatCount: 255, timeout: .seconds(12), retryCount: 0)
        } catch let error as PumpOpsError {
            throw PumpCommandError.command(error)
        }
    }

    private func isPumpResponding() -> Bool {
        do {
            let _: GetPumpModelCarelinkMessageBody = try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .getPumpModel), responseType: .getPumpModel, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 1)
            return true
        } catch {
            return false
        }
    }

    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///         - PumpOpsError.couldNotDecode
    ///         - PumpOpsError.crosstalk
    ///         - PumpOpsError.deviceError
    ///         - PumpOpsError.noResponse
    ///         - PumpOpsError.unexpectedResponse
    ///         - PumpOpsError.unknownResponse
    private func wakeup(_ duration: TimeInterval = TimeInterval(minutes: 1)) throws {
        guard !pump.isAwake else {
            return
        }

        // Send a short message to the pump to see if its radio is still powered on
        if isPumpResponding() {
            // TODO: Convert logging
            NSLog("Pump responding despite our wake timer having expired. Extending timer")
            // By my observations, the pump stays awake > 1 minute past last comms. Usually
            // About 1.5 minutes, but we'll make it a minute to be safe.
            pump.awakeUntil = Date(timeIntervalSinceNow: TimeInterval(minutes: 1))
            return
        }

        // Command
        try sendWakeUpBurst()

        // Arguments
        do {
            let longPowerMessage = PumpMessage(pumpID: settings.pumpID, type: .powerOn, body: PowerOnCarelinkMessageBody(duration: duration))
            let _: PumpAckMessageBody = try messageSender.getResponse(to: longPowerMessage, responseType: .pumpAck, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
        } catch let error as PumpOpsError {
            throw PumpCommandError.arguments(error)
        } catch {
            assertionFailure()
        }

        // TODO: Convert logging
        NSLog("Power on for %.0f minutes", duration.minutes)
        pump.awakeUntil = Date(timeIntervalSinceNow: duration)
    }
}

// MARK: - Single reads
extension PumpOpsSession {
    /// Retrieves the pump model from either the state or from the cache
    ///
    /// - Parameter usingCache: Whether the pump state should be checked first for a known pump model
    /// - Returns: The pump model
    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func getPumpModel(usingCache: Bool = true) throws -> PumpModel {
        if usingCache, let pumpModel = pump.pumpModel {
            return pumpModel
        }

        try wakeup()
        let body: GetPumpModelCarelinkMessageBody = try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .getPumpModel), responseType: .getPumpModel, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)

        guard let pumpModel = PumpModel(rawValue: body.model) else {
            throw PumpOpsError.unknownPumpModel(body.model)
        }

        pump.pumpModel = pumpModel

        return pumpModel
    }

    /// Retrieves the pump firmware version
    ///
    /// - Returns: The pump firmware version as string
    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func getPumpFirmwareVersion() throws -> String {
        
        try wakeup()
        let body: GetPumpFirmwareVersionMessageBody = try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readFirmwareVersion), responseType: .readFirmwareVersion, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
        
        return body.version
    }

    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func getBatteryStatus() throws -> GetBatteryCarelinkMessageBody {
        try wakeup()
        return try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .getBattery), responseType: .getBattery, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
    }

    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    internal func getPumpStatus() throws -> ReadPumpStatusMessageBody {
        try wakeup()
        return try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readPumpStatus), responseType: .readPumpStatus, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
    }

    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func getSettings() throws -> ReadSettingsCarelinkMessageBody {
        try wakeup()
        return try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readSettings), responseType: .readSettings, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
    }

    /// Reads the pump's time, returning a set of DateComponents in the pump's presumed time zone.
    ///
    /// - Returns: The pump's time components including timeZone
    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func getTime() throws -> DateComponents {
        try wakeup()
        let response: ReadTimeCarelinkMessageBody = try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readTime), responseType: .readTime, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
        var components = response.dateComponents
        components.timeZone = pump.timeZone
        return components
    }

    /// Reads Basal Schedule from the pump
    ///
    /// - Returns: The pump's standard basal schedule
    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func getBasalSchedule(for profile: BasalProfile = .standard) throws -> BasalSchedule? {
        try wakeup()

        var isFinished = false
        var message = PumpMessage(pumpID: settings.pumpID, type: profile.readMessageType)
        var scheduleData = Data()
        while (!isFinished) {
            let body: DataFrameMessageBody = try messageSender.getResponse(to: message, responseType: profile.readMessageType, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)

            scheduleData.append(body.contents)
            isFinished = body.isLastFrame
            message = PumpMessage(pumpID: settings.pumpID, type: .pumpAck)
        }

        return BasalSchedule(rawValue: scheduleData)
    }

    /// - Throws:
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func getOtherDevicesIDs() throws -> ReadOtherDevicesIDsMessageBody {
        try wakeup()

        return try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readOtherDevicesIDs), responseType: .readOtherDevicesIDs, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
    }

    /// - Throws:
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func getOtherDevicesEnabled() throws -> Bool {
        try wakeup()

        let response: ReadOtherDevicesStatusMessageBody = try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readOtherDevicesStatus), responseType: .readOtherDevicesStatus, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
        return response.isEnabled
    }

    /// - Throws:
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func getRemoteControlIDs() throws -> ReadRemoteControlIDsMessageBody {
        try wakeup()

        return try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readRemoteControlIDs), responseType: .readRemoteControlIDs, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
    }
}


// MARK: - Aggregate reads
public struct PumpStatus: Equatable {
    // Date components read from the pump, along with PumpState.timeZone
    public let clock: DateComponents
    public let batteryVolts: Measurement<UnitElectricPotentialDifference>
    public let batteryStatus: BatteryStatus
    public let suspended: Bool
    public let bolusing: Bool
    public let reservoir: Double
    public let model: PumpModel
    public let pumpID: String
}


extension PumpOpsSession {
    /// Reads the current insulin reservoir volume and the pump's date
    ///
    /// - Returns:
    ///     - The reservoir volume, in units of insulin
    ///     - DateCompoments representing the pump's clock
    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unknownResponse
    public func getRemainingInsulin() throws -> (units: Double, clock: DateComponents) {

        let pumpModel = try getPumpModel()
        let pumpClock = try getTime()

        let reservoir: ReadRemainingInsulinMessageBody = try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readRemainingInsulin), responseType: .readRemainingInsulin, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)

        return (
            units: reservoir.getUnitsRemaining(insulinBitPackingScale: pumpModel.insulinBitPackingScale),
            clock: pumpClock
        )
    }

    /// Reads clock, reservoir, battery, bolusing, and suspended state from pump
    ///
    /// - Returns: The pump status
    /// - Throws:
    ///     - PumpCommandError
    ///     - PumpOpsError
    public func getCurrentPumpStatus() throws -> PumpStatus {
        let pumpModel = try getPumpModel()

        let battResp = try getBatteryStatus()

        let status = try getPumpStatus()

        let (reservoir, clock) = try getRemainingInsulin()

        return PumpStatus(
            clock: clock,
            batteryVolts: Measurement(value: battResp.volts, unit: UnitElectricPotentialDifference.volts),
            batteryStatus: battResp.status,
            suspended: status.suspended,
            bolusing: status.bolusing,
            reservoir: reservoir,
            model: pumpModel,
            pumpID: settings.pumpID
        )
    }
}


// MARK: - Command messages
extension PumpOpsSession {

    enum CommandTestingFailureMode {
        case argumentFailureDoSendArguments
        case argumentFailureDoNotSendArguments
    }

    /// - Throws: `PumpCommandError` specifying the failure sequence
    private func runCommandWithArguments<T: MessageBody>(_ message: PumpMessage, responseType: MessageType = .pumpAck, retryCount: Int = 3, testingFailureMode: CommandTestingFailureMode? = nil) throws -> T {
        do {
            try wakeup()

            let shortMessage = PumpMessage(packetType: message.packetType, address: message.address.hexadecimalString, messageType: message.messageType, messageBody: CarelinkShortMessageBody())
            let _: PumpAckMessageBody = try messageSender.getResponse(to: shortMessage, responseType: .pumpAck, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
        } catch let error as PumpOpsError {
            throw PumpCommandError.command(error)
        }

        do {
            if testingFailureMode == .argumentFailureDoNotSendArguments {
                throw PumpOpsError.noResponse(during: "argumentFailureDoNotSendArguments")
            }
            let response: T = try messageSender.getResponse(to: message, responseType: responseType, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: retryCount)
            if testingFailureMode == .argumentFailureDoSendArguments {
                throw PumpOpsError.noResponse(during: "argumentFailureDoSendArguments")
            }
            return response

        } catch let error as PumpOpsError {
            throw PumpCommandError.arguments(error)
        }
    }

    /// - Throws: `PumpCommandError` specifying the failure sequence
    public func pressButton(_ type: ButtonPressCarelinkMessageBody.ButtonType) throws {
        let message = PumpMessage(pumpID: settings.pumpID, type: .buttonPress, body: ButtonPressCarelinkMessageBody(buttonType: type))

        let _: PumpAckMessageBody = try runCommandWithArguments(message)
    }
    
    /// - Throws: `PumpCommandError` specifying the failure sequence
    public func setSuspendResumeState(_ state: SuspendResumeMessageBody.SuspendResumeState) throws {
        let message = PumpMessage(pumpID: settings.pumpID, type: .suspendResume, body: SuspendResumeMessageBody(state: state))
        
        let _: PumpAckMessageBody = try runCommandWithArguments(message)
    }

    /// - Throws: PumpCommandError
    public func selectBasalProfile(_ profile: BasalProfile) throws {
        let message = PumpMessage(pumpID: settings.pumpID, type: .selectBasalProfile, body: SelectBasalProfileMessageBody(newProfile: profile))

        let _: PumpAckMessageBody = try runCommandWithArguments(message)
    }

    /// - Throws: PumpCommandError
    public func setMaxBasalRate(unitsPerHour: Double) throws {
        guard let body = ChangeMaxBasalRateMessageBody(maxBasalUnitsPerHour: unitsPerHour) else {
            throw PumpCommandError.command(PumpOpsError.pumpError(PumpErrorCode.maxSettingExceeded))
        }

        let message = PumpMessage(pumpID: settings.pumpID, type: .setMaxBasalRate, body: body)

        let _: PumpAckMessageBody = try runCommandWithArguments(message)
    }

    /// - Throws: PumpCommandError
    public func setMaxBolus(units: Double) throws {
        guard let body = ChangeMaxBolusMessageBody(pumpModel: try getPumpModel(), maxBolusUnits: units) else {
            throw PumpCommandError.command(PumpOpsError.pumpError(PumpErrorCode.maxSettingExceeded))
        }

        let message = PumpMessage(pumpID: settings.pumpID, type: .setMaxBolus, body: body)

        let _: PumpAckMessageBody = try runCommandWithArguments(message)
    }

    /// Changes the current temporary basal rate
    ///
    /// - Parameters:
    ///   - unitsPerHour: The new basal rate, in Units per hour
    ///   - duration: The duration of the rate
    /// - Returns:
    ///   - .success: A bool that indicates if the dose was confirmed successful
    ///   - .failure: An error describing why the command failed
    public func setTempBasal(_ unitsPerHour: Double, duration: TimeInterval) -> Result<Bool,PumpCommandError> {

        let message = PumpMessage(pumpID: settings.pumpID, type: .changeTempBasal, body: ChangeTempBasalCarelinkMessageBody(unitsPerHour: unitsPerHour, duration: duration))

        do {
            try wakeup()
        } catch {
            // Certain failure, as we haven't sent actual command yet; wakeup failed
            return .failure(.command(error as? PumpOpsError ?? PumpOpsError.rfCommsFailure(String(describing: error))))
        }

        do {
            let shortMessage = PumpMessage(packetType: message.packetType, address: message.address.hexadecimalString, messageType: message.messageType, messageBody: CarelinkShortMessageBody())
            let _: PumpAckMessageBody = try messageSender.getResponse(to: shortMessage, responseType: .pumpAck, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
        } catch {
            // Certain failure, as we haven't sent actual command yet; just preflight short command
            return .failure(.command(error as? PumpOpsError ?? PumpOpsError.rfCommsFailure(String(describing: error))))
        }

        var uncertainFailureError: PumpCommandError?

        do {
            let _: PumpAckMessageBody = try messageSender.getResponse(to: message, responseType: .pumpAck, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 1)
            // Even in success case, we try to verify, below
        } catch PumpOpsError.pumpError(let errorCode) {
            return .failure(.arguments(.pumpError(errorCode)))
        } catch PumpOpsError.unknownPumpErrorCode(let errorCode) {
            return .failure(.arguments(.unknownPumpErrorCode(errorCode)))
        } catch {
            // Some pumps do not ACK a successful temp basal. Check manually to see if it was successful.
            uncertainFailureError = .command(error as? PumpOpsError ?? PumpOpsError.rfCommsFailure(String(describing: error)))
        }

        do {
            let response: ReadTempBasalCarelinkMessageBody = try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readTempBasal), responseType: .readTempBasal, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
            // Duration is always whole minute values
            if response.timeRemaining == duration && response.rateType == .absolute {
                return .success(true)
            } else {
                // readTempBasal does not match what we attempted to command
                if let failureError = uncertainFailureError {
                    return .failure(failureError)
                }
                // successful readTempBasal shows no temp basal running, so we failed
                return .failure(PumpCommandError.arguments(PumpOpsError.rfCommsFailure("Confirmed that temp basal failed, and ")))
            }
        } catch {
            // unsuccessful readTempBasal; assume command reached pump, but we're uncertain
            return .success(false)
        }
    }

    /// Changes the pump's clock to the specified date components in the system time zone
    ///
    /// - Parameter generator: A closure which returns the desired date components. An exeception is raised if the date components are not valid.
    /// - Throws: PumpCommandError
    public func setTime(_ generator: () -> DateComponents) throws {
        try wakeup()

        do {
            let shortMessage = PumpMessage(pumpID: settings.pumpID, type: .changeTime)
            let _: PumpAckMessageBody = try messageSender.getResponse(to: shortMessage, responseType: .pumpAck, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
        } catch let error as PumpOpsError {
            throw PumpCommandError.command(error)
        }

        do {
            let components = generator()
            let message = PumpMessage(pumpID: settings.pumpID, type: .changeTime, body: ChangeTimeCarelinkMessageBody(dateComponents: components)!)
            let _: PumpAckMessageBody = try messageSender.getResponse(to: message, responseType: .pumpAck, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
            self.pump.timeZone = components.timeZone?.fixed ?? .currentFixed
        } catch let error as PumpOpsError {
            throw PumpCommandError.arguments(error)
        }
    }

    public func setTimeToNow(in timeZone: TimeZone? = nil) throws {
        let timeZone = timeZone ?? pump.timeZone

        try setTime { () -> DateComponents in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
            components.timeZone = timeZone
            return components
        }
    }

    /// Sets a bolus
    ///
    /// *Note: Use at your own risk!*
    ///
    /// - Parameters:
    ///   - units: The number of units to deliver
    ///   - cancelExistingTemp: If true, additional pump commands will be issued to clear any running temp basal. Defaults to false.
    /// - Returns: SetBolusError if the command failed
    public func setNormalBolus(units: Double) -> SetBolusError? {
        let pumpModel: PumpModel

        do {
            try wakeup()
            pumpModel = try getPumpModel()

            let status = try getPumpStatus()

            if status.bolusing {
                throw PumpOpsError.bolusInProgress
            }

            if status.suspended {
                throw PumpOpsError.pumpSuspended
            }

        } catch let error as PumpOpsError {
            return SetBolusError.certain(error)
        } catch let error as PumpCommandError {
            switch error {
            case .command(let error):
                return SetBolusError.certain(error)
            case .arguments(let error):
                return SetBolusError.certain(error)
            }
        } catch {
            return SetBolusError.certain(PumpOpsError.rfCommsFailure(String(describing: error)))
        }

        do {
            let message = PumpMessage(pumpID: settings.pumpID, type: .bolus, body: BolusCarelinkMessageBody(units: units, insulinBitPackingScale: pumpModel.insulinBitPackingScale))

            let testMode: CommandTestingFailureMode? = nil

            // Uncomment for manual testing of uncertain delivery states
//            if units == 9.05 {
//                testMode = .argumentFailureDoNotSendArguments
//            } else if units == 8.05 {
//                testMode = .argumentFailureDoSendArguments
//            } else {
//                testMode = nil
//            }

            let _: PumpAckMessageBody = try runCommandWithArguments(message, testingFailureMode: testMode)
        } catch let error as PumpOpsError {
            return SetBolusError.certain(error)
        } catch let error as PumpCommandError {
            switch error {
            case .command(let error):
                return SetBolusError.certain(error)
            case .arguments(let error):
                return SetBolusError.uncertain(error)
            }
        } catch {
            assertionFailure()
        }
        return nil
    }

    /// - Throws: PumpCommandError
    public func setRemoteControlEnabled(_ enabled: Bool) throws {
        let message = PumpMessage(pumpID: settings.pumpID, type: .setRemoteControlEnabled, body: SetRemoteControlEnabledMessageBody(enabled: enabled))

        let _: PumpAckMessageBody = try runCommandWithArguments(message)
    }

    /// - Throws: PumpCommandError
    public func setRemoteControlID(_ id: Data, atIndex index: Int) throws {
        guard let body = ChangeRemoteControlIDMessageBody(id: id, index: index) else {
            throw PumpCommandError.command(PumpOpsError.pumpError(PumpErrorCode.maxSettingExceeded))
        }

        let message = PumpMessage(pumpID: settings.pumpID, type: .setRemoteControlID, body: body)

        let _: PumpAckMessageBody = try runCommandWithArguments(message)
    }

    /// - Throws: PumpCommandError
    public func removeRemoteControlID(atIndex index: Int) throws {
        guard let body = ChangeRemoteControlIDMessageBody(id: nil, index: index) else {
            throw PumpCommandError.command(PumpOpsError.pumpError(PumpErrorCode.maxSettingExceeded))
        }

        let message = PumpMessage(pumpID: settings.pumpID, type: .setRemoteControlID, body: body)

        let _: PumpAckMessageBody = try runCommandWithArguments(message)
    }

    /// - Throws: `PumpCommandError` specifying the failure sequence
    public func setBasalSchedule(_ basalSchedule: BasalSchedule, for profile: BasalProfile) throws {

        let frames = DataFrameMessageBody.dataFramesFromContents(basalSchedule.rawValue)

        guard let firstFrame = frames.first else {
            return
        }

        let type: MessageType
        switch profile {
        case .standard:
            type = .setBasalProfileStandard
        case .profileA:
            type = .setBasalProfileA
        case .profileB:
            type = .setBasalProfileB
        }

        let message = PumpMessage(pumpID: settings.pumpID, type: type, body: firstFrame)
        let _: PumpAckMessageBody = try runCommandWithArguments(message)

        for nextFrame in frames.dropFirst() {
            let message = PumpMessage(pumpID: settings.pumpID, type: type, body: nextFrame)
            do {
                let _: PumpAckMessageBody = try messageSender.getResponse(to: message, responseType: .pumpAck, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
            } catch let error as PumpOpsError {
                throw PumpCommandError.arguments(error)
            }
        }
    }
    
    public func getStatistics() throws -> RileyLinkStatistics {
        return try messageSender.getRileyLinkStatistics()
    }
}


// MARK: - MySentry (Watchdog) pairing
extension PumpOpsSession {
    /// Pairs the pump with a virtual "watchdog" device to enable it to broadcast periodic status packets. Only pump models x23 and up are supported.
    ///
    /// - Parameter watchdogID: A 3-byte address for the watchdog device.
    /// - Throws:
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    public func changeWatchdogMarriageProfile(_ watchdogID: Data) throws {
        let commandTimeout = TimeInterval(seconds: 30)

        // Wait for the pump to start polling
        guard let encodedData = try messageSender.listenForPacket(onChannel: 0, timeout: commandTimeout)?.data else {
            throw PumpOpsError.noResponse(during: "Watchdog listening")
        }

        guard let packet = MinimedPacket(encodedData: encodedData) else {
            throw PumpOpsError.couldNotDecode(rx: encodedData, during: "Watchdog listening")
        }
        
        guard let findMessage = PumpMessage(rxData: packet.data) else {
            // Unknown packet type or message type
            throw PumpOpsError.unknownResponse(rx: packet.data, during: "Watchdog listening")
        }

        guard findMessage.address.hexadecimalString == settings.pumpID && findMessage.packetType == .mySentry,
            let findMessageBody = findMessage.messageBody as? FindDeviceMessageBody, let findMessageResponseBody = MySentryAckMessageBody(sequence: findMessageBody.sequence, watchdogID: watchdogID, responseMessageTypes: [findMessage.messageType])
        else {
            throw PumpOpsError.unknownResponse(rx: packet.data, during: "Watchdog listening")
        }

        // Identify as a MySentry device
        let findMessageResponse = PumpMessage(packetType: .mySentry, address: settings.pumpID, messageType: .pumpAck, messageBody: findMessageResponseBody)

        let linkMessage = try messageSender.sendAndListen(findMessageResponse, repeatCount: 0, timeout: commandTimeout, retryCount: 3)

        guard let
            linkMessageBody = linkMessage.messageBody as? DeviceLinkMessageBody,
            let linkMessageResponseBody = MySentryAckMessageBody(sequence: linkMessageBody.sequence, watchdogID: watchdogID, responseMessageTypes: [linkMessage.messageType])
        else {
            throw PumpOpsError.unexpectedResponse(linkMessage, from: findMessageResponse)
        }

        // Acknowledge the pump linked with us
        let linkMessageResponse = PumpMessage(packetType: .mySentry, address: settings.pumpID, messageType: .pumpAck, messageBody: linkMessageResponseBody)

        try messageSender.send(linkMessageResponse)
    }
}


// MARK: - Tuning
private extension PumpRegion {
    var scanFrequencies: [Measurement<UnitFrequency>] {
        let scanFrequencies: [Double]

        switch self {
        case .worldWide:
            scanFrequencies = [868.25, 868.30, 868.35, 868.40, 868.45, 868.50, 868.55, 868.60, 868.65]
        case .northAmerica, .canada:
            scanFrequencies = [916.45, 916.50, 916.55, 916.60, 916.65, 916.70, 916.75, 916.80]
        }

        return scanFrequencies.map {
            return Measurement<UnitFrequency>(value: $0, unit: .megahertz)
        }
    }
}

enum RXFilterMode: UInt8 {
    case wide   = 0x50  // 300KHz
    case narrow = 0x90  // 150KHz
}

public struct FrequencyTrial {
    public var tries: Int = 0
    public var successes: Int = 0
    public var avgRSSI: Double = -99
    public var frequency: Measurement<UnitFrequency>

    init(frequency: Measurement<UnitFrequency>) {
        self.frequency = frequency
    }
}

public struct FrequencyScanResults {
    public var trials: [FrequencyTrial]
    public var bestFrequency: Measurement<UnitFrequency>
}

extension PumpOpsSession {
    /// - Throws:
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.rfCommsFailure
    public func tuneRadio(attempts: Int = 3) throws -> FrequencyScanResults {
        let region = self.settings.pumpRegion

        do {
            let results = try scanForPump(in: region.scanFrequencies, fallback: pump.lastValidFrequency, tries: attempts)
            
            pump.lastValidFrequency = results.bestFrequency
            pump.lastTuned = Date()
            
            delegate.pumpOpsSessionDidChangeRadioConfig(self)

            return results
        } catch let error as PumpOpsError {
            throw error
        } catch let error as LocalizedError {
            throw PumpOpsError.deviceError(error)
        }
    }

    /// - Throws: PumpOpsError.deviceError
    private func setRXFilterMode(_ mode: RXFilterMode) throws {
        let drate_e = UInt8(0x9) // exponent of symbol rate (16kbps)
        let chanbw = mode.rawValue
        do {
            try messageSender.updateRegister(.mdmcfg4, value: chanbw | drate_e)
        } catch let error as LocalizedError {
            throw PumpOpsError.deviceError(error)
        }
    }

    /// - Throws:
    ///     - PumpOpsError.deviceError
    ///     - RileyLinkDeviceError
    func configureRadio(for region: PumpRegion, frequency: Measurement<UnitFrequency>?) throws {
        try messageSender.resetRadioConfig()
        
        switch region {
        case .worldWide:
            //try session.updateRegister(.mdmcfg4, value: 0x59)
            try setRXFilterMode(.wide)
            //try session.updateRegister(.mdmcfg3, value: 0x66)
            //try session.updateRegister(.mdmcfg2, value: 0x33)
            try messageSender.updateRegister(.mdmcfg1, value: 0x62)
            try messageSender.updateRegister(.mdmcfg0, value: 0x1A)
            try messageSender.updateRegister(.deviatn, value: 0x13)
        case .northAmerica, .canada:
            //try session.updateRegister(.mdmcfg4, value: 0x99)
            try setRXFilterMode(.narrow)
            //try session.updateRegister(.mdmcfg3, value: 0x66)
            //try session.updateRegister(.mdmcfg2, value: 0x33)
            try messageSender.updateRegister(.mdmcfg1, value: 0x61)
            try messageSender.updateRegister(.mdmcfg0, value: 0x7E)
            try messageSender.updateRegister(.deviatn, value: 0x15)
        }
        
        if let frequency = frequency {
            try messageSender.setBaseFrequency(frequency)
        }
    }

    /// - Throws:
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.rfCommsFailure
    ///     - LocalizedError
    private func scanForPump(in frequencies: [Measurement<UnitFrequency>], fallback: Measurement<UnitFrequency>?, tries: Int = 3) throws -> FrequencyScanResults {
        
        var trials = [FrequencyTrial]()
        
        let middleFreq = frequencies[frequencies.count / 2]
        
        do {
            // Needed to put the pump in listen mode
            try messageSender.setBaseFrequency(middleFreq)
            try wakeup()
        } catch {
            // Continue anyway; the pump likely heard us, even if we didn't hear it.
        }
        
        for freq in frequencies {
            var trial = FrequencyTrial(frequency: freq)

            try messageSender.setBaseFrequency(freq)
            var sumRSSI = 0
            for _ in 1...tries {
                // Ignore failures here
                let rfPacket = try? messageSender.sendAndListenForPacket(PumpMessage(pumpID: settings.pumpID, type: .getPumpModel), repeatCount: 0, timeout: .milliseconds(130), retryCount: 3)
                if  let rfPacket = rfPacket,
                    let pkt = MinimedPacket(encodedData: rfPacket.data),
                    let response = PumpMessage(rxData: pkt.data), response.messageType == .getPumpModel
                {
                    sumRSSI += rfPacket.rssi
                    trial.successes += 1
                }
                trial.tries += 1
            }
            // Mark each failure as a -99 rssi, so we can use highest rssi as best freq
            sumRSSI += -99 * (trial.tries - trial.successes)
            trial.avgRSSI = Double(sumRSSI) / Double(trial.tries)
            trials.append(trial)
        }
        let sortedTrials = trials.sorted(by: { (a, b) -> Bool in
            return a.avgRSSI > b.avgRSSI
        })

        guard sortedTrials.first!.successes > 0 else {
            try messageSender.setBaseFrequency(fallback ?? middleFreq)
            throw PumpOpsError.rfCommsFailure("No pump responses during scan")
        }

        let results = FrequencyScanResults(
            trials: trials,
            bestFrequency: sortedTrials.first!.frequency
        )
        
        try messageSender.setBaseFrequency(results.bestFrequency)

        return results
    }
}


// MARK: - Pump history
extension PumpOpsSession {
    /// Fetches history entries which occurred on or after the specified date.
    ///
    /// It is possible for Minimed Pumps to non-atomically append multiple history entries with the same timestamp, for example, `BolusWizardEstimatePumpEvent` may appear and be read before `BolusNormalPumpEvent` is written. Therefore, the `startDate` parameter is used as part of an inclusive range, leaving the client to manage the possibility of duplicates.
    ///
    /// History timestamps are reconciled with UTC based on the `timeZone` property of PumpState, as well as recorded clock change events.
    ///
    /// - Parameter startDate: The earliest date of events to retrieve
    /// - Returns:
    ///     - An array of fetched history entries, in ascending order of insertion
    ///     - The pump model
    /// - Throws:
    ///     - PumpCommandError.command
    ///     - PumpCommandError.arguments
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unknownResponse
    ///     - HistoryPageError.invalidCRC
    ///     - HistoryPageError.unknownEventType
    public func getHistoryEvents(since startDate: Date) throws -> ([TimestampedHistoryEvent], PumpModel) {
        try wakeup()

        let pumpModel = try getPumpModel()
        
        var events = [TimestampedHistoryEvent]()
        
        pages: for pageNum in 0..<16 {
            // TODO: Convert logging
            NSLog("Fetching page %d", pageNum)
            let pageData: Data

            do {
                pageData = try getHistoryPage(pageNum)
            } catch PumpCommandError.arguments(let error) {
                if case PumpOpsError.pumpError(.pageDoesNotExist) = error {
                    return (events, pumpModel)
                }
                throw PumpCommandError.arguments(error)
            }
            
            var idx = 0
            let chunkSize = 256
            while idx < pageData.count {
                let top = min(idx + chunkSize, pageData.count)
                let range = Range(uncheckedBounds: (lower: idx, upper: top))
                // TODO: Convert logging
                NSLog(String(format: "HistoryPage %02d - (bytes %03d-%03d): ", pageNum, idx, top-1) + pageData.subdata(in: range).hexadecimalString)
                idx = top
            }

            let page = try HistoryPage(pageData: pageData, pumpModel: pumpModel)
            
            let (timestampedEvents, hasMoreEvents, _) = page.timestampedEvents(after: startDate, timeZone: pump.timeZone, model: pumpModel)

            events = timestampedEvents + events
            
            if !hasMoreEvents {
                break
            }
        }
        return (events, pumpModel)
    }
    
    private func getHistoryPage(_ pageNum: Int) throws -> Data {
        var frameData = Data()
        
        let msg = PumpMessage(pumpID: settings.pumpID, type: .getHistoryPage, body: GetHistoryPageCarelinkMessageBody(pageNum: pageNum))
        
        var curResp: GetHistoryPageCarelinkMessageBody = try runCommandWithArguments(msg, responseType: .getHistoryPage)

        var expectedFrameNum = 1
        
        while(expectedFrameNum == curResp.frameNumber) {
            frameData.append(curResp.frame)
            expectedFrameNum += 1
            let msg = PumpMessage(pumpID: settings.pumpID, type: .pumpAck)
            if !curResp.lastFrame {
                curResp = try messageSender.getResponse(to: msg, responseType: .getHistoryPage, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
            } else {
                try messageSender.send(msg)
                break
            }
        }
        
        guard frameData.count == 1024 else {
            throw PumpOpsError.rfCommsFailure("Short history page: \(frameData.count) bytes. Expected 1024")
        }
        return frameData
    }
}


// MARK: - Glucose history
extension PumpOpsSession {
    private func logGlucoseHistory(pageData: Data, pageNum: Int) {
        var idx = 0
        let chunkSize = 256
        while idx < pageData.count {
            let top = min(idx + chunkSize, pageData.count)
            let range = Range(uncheckedBounds: (lower: idx, upper: top))
            // TODO: Convert logging
            NSLog(String(format: "GlucosePage %02d - (bytes %03d-%03d): ", pageNum, idx, top-1) + pageData.subdata(in: range).hexadecimalString)
            idx = top
        }
    }
    
    /// Fetches glucose history entries which occurred on or after the specified date.
    ///
    /// History timestamps are reconciled with UTC based on the `timeZone` property of PumpState, as well as recorded clock change events.
    ///
    /// - Parameter startDate: The earliest date of events to retrieve
    /// - Returns: An array of fetched history entries, in ascending order of insertion
    /// - Throws: 
    public func getGlucoseHistoryEvents(since startDate: Date) throws -> [TimestampedGlucoseEvent] {
        try wakeup()
        
        var events = [TimestampedGlucoseEvent]()
        
        let currentGlucosePage: ReadCurrentGlucosePageMessageBody = try messageSender.getResponse(to: PumpMessage(pumpID: settings.pumpID, type: .readCurrentGlucosePage), responseType: .readCurrentGlucosePage, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
        let startPage = Int(currentGlucosePage.pageNum)
        //max lookback of 15 pages or when page is 0
        let endPage = max(startPage - 15, 0)
        
        pages: for pageNum in stride(from: startPage, to: endPage - 1, by: -1) {
            // TODO: Convert logging
            NSLog("Fetching page %d", pageNum)
            var pageData: Data
            var page: GlucosePage
            
            do {
                pageData = try getGlucosePage(UInt32(pageNum))
                // logGlucoseHistory(pageData: pageData, pageNum: pageNum)
                page = try GlucosePage(pageData: pageData)
                
                if page.needsTimestamp && pageNum == startPage {
                    // TODO: Convert logging
                    NSLog(String(format: "GlucosePage %02d needs a new sensor timestamp, writing...", pageNum))
                    let _ = try writeGlucoseHistoryTimestamp()
                    
                    //fetch page again with new sensor timestamp
                    pageData = try getGlucosePage(UInt32(pageNum))
                    logGlucoseHistory(pageData: pageData, pageNum: pageNum)
                    page = try GlucosePage(pageData: pageData)
                }
            } catch PumpOpsError.pumpError {
                break pages
            }
            
            for event in page.events.reversed() {
                var timestamp = event.timestamp
                timestamp.timeZone = pump.timeZone
                
                if event is UnknownGlucoseEvent {
                    continue pages
                }
                
                if let date = timestamp.date {
                    if date < startDate && event is SensorTimestampGlucoseEvent {
                        // TODO: Convert logging
                        NSLog("Found reference event at (%@) to be before startDate(%@)", date as NSDate, startDate as NSDate)
                        break pages
                    } else {
                        events.insert(TimestampedGlucoseEvent(glucoseEvent: event, date: date), at: 0)
                    }
                }
            }
        }
        return events
    }

    private func getGlucosePage(_ pageNum: UInt32) throws -> Data {
        var frameData = Data()
        
        let msg = PumpMessage(pumpID: settings.pumpID, type: .getGlucosePage, body: GetGlucosePageMessageBody(pageNum: pageNum))

        var curResp: GetGlucosePageMessageBody = try runCommandWithArguments(msg, responseType: .getGlucosePage)
        
        var expectedFrameNum = 1
        
        while(expectedFrameNum == curResp.frameNumber) {
            frameData.append(curResp.frame)
            expectedFrameNum += 1
            let msg = PumpMessage(pumpID: settings.pumpID, type: .pumpAck)
            if !curResp.lastFrame {
                curResp = try messageSender.getResponse(to: msg, responseType: .getGlucosePage, repeatCount: 0, timeout: MinimedPumpMessageSender.standardPumpResponseWindow,  retryCount: 3)
            } else {
                try messageSender.send(msg)
                break
            }
        }
        
        guard frameData.count == 1024 else {
            throw PumpOpsError.rfCommsFailure("Short glucose history page: \(frameData.count) bytes. Expected 1024")
        }
        return frameData
    }
    
    public func writeGlucoseHistoryTimestamp() throws -> Void {
        try wakeup()

        let shortWriteTimestamp = PumpMessage(pumpID: settings.pumpID, type: .writeGlucoseHistoryTimestamp)
        let _: PumpAckMessageBody = try messageSender.getResponse(to: shortWriteTimestamp, responseType: .pumpAck, repeatCount: 0, timeout: .seconds(12),  retryCount: 3)
    }
}
