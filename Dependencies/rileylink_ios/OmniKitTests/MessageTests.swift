//
//  MessageTests.swift
//  OmniKitTests
//
//  Created by Pete Schwamb on 10/14/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import OmniKit

class MessageTests: XCTestCase {
    
    func testMessageData() {
        // 2016-06-26T20:33:28.412197 ID1:1f01482a PTYPE:PDM SEQ:13 ID2:1f01482a B9:10 BLEN:3 BODY:0e0100802c CRC:88
        
        let msg = Message(address: 0x1f01482a, messageBlocks: [GetStatusCommand()], sequenceNum: 4)
        
        XCTAssertEqual("1f01482a10030e0100802c", msg.encoded().hexadecimalString)
    }
    
    func testMessageDecoding() {
        do {
            let msg = try Message(encodedData: Data(hexadecimalString: "1f00ee84300a1d18003f1800004297ff8128")!)
            
            XCTAssertEqual(0x1f00ee84, msg.address)
            XCTAssertEqual(12, msg.sequenceNum)
            
            let messageBlocks = msg.messageBlocks
            
            XCTAssertEqual(1, messageBlocks.count)
            
            let statusResponse = messageBlocks[0] as! StatusResponse
            
            XCTAssertEqual(Pod.reservoirLevelAboveThresholdMagicNumber, statusResponse.reservoirLevel, accuracy: 0.01)
            XCTAssertEqual(TimeInterval(minutes: 4261), statusResponse.timeActive)

            XCTAssertEqual(.scheduledBasal, statusResponse.deliveryStatus)
            XCTAssertEqual(.aboveFiftyUnits, statusResponse.podProgressStatus)
            XCTAssertEqual(6.3, statusResponse.insulinDelivered, accuracy: 0.01)
            XCTAssertEqual(0, statusResponse.bolusNotDelivered)
            XCTAssertEqual(3, statusResponse.lastProgrammingMessageSeqNum)
            XCTAssert(statusResponse.alerts.isEmpty)

            XCTAssertEqual("1f00ee84300a1d18003f1800004297ff8128", msg.encoded().hexadecimalString)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testAssemblingMultiPacketMessage() {
        do {
            let packet1 = try Packet(encodedData: Data(hexadecimalString: "ffffffffe4ffffffff041d011b13881008340a5002070002070002030000a62b0004479420")!)
            XCTAssertEqual(packet1.data.hexadecimalString, "ffffffff041d011b13881008340a5002070002070002030000a62b00044794")
            XCTAssertEqual(packet1.packetType, .pod)

            XCTAssertThrowsError(try Message(encodedData: packet1.data)) { error in
                XCTAssertEqual(String(describing: error), "notEnoughData")
            }
            
            let packet2 = try Packet(encodedData: Data(hexadecimalString: "ffffffff861f00ee878352ff")!)
            XCTAssertEqual(packet2.address, 0xffffffff)
            XCTAssertEqual(packet2.data.hexadecimalString, "1f00ee878352")
            XCTAssertEqual(packet2.packetType, .con)
            
            let messageBody = packet1.data + packet2.data
            XCTAssertEqual(messageBody.hexadecimalString, "ffffffff041d011b13881008340a5002070002070002030000a62b000447941f00ee878352")

            let message = try Message(encodedData: messageBody)
            XCTAssertEqual(message.messageBlocks.count, 1)

        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testParsingShortErosVersionResponse() {
        do {
            let config = try VersionResponse(encodedData: Data(hexadecimalString: "011502070002070002020000a64000097c279c1f08ced2")!)
            XCTAssertEqual(23, config.data.count)
            XCTAssertEqual("2.7.0", String(describing: config.firmwareVersion))
            XCTAssertEqual("2.7.0", String(describing: config.iFirmwareVersion))
            XCTAssertEqual(42560, config.lot)
            XCTAssertEqual(621607, config.tid)
            XCTAssertEqual(0x1f08ced2, config.address)
            XCTAssertEqual(2, config.productId)
            XCTAssertEqual(.reminderInitialized, config.podProgressStatus)
            XCTAssertEqual(2, config.gain)
            XCTAssertEqual(0x1c, config.rssi)
            XCTAssertNil(config.pulseSize)
            XCTAssertNil(config.secondsPerBolusPulse)
            XCTAssertNil(config.secondsPerPrimePulse)
            XCTAssertNil(config.primeUnits)
            XCTAssertNil(config.cannulaInsertionUnits)
            XCTAssertNil(config.serviceDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testParsingLongErosVersionResponse() {
        do {
            let message = try Message(encodedData: Data(hexadecimalString: "ffffffff041d011b13881008340a5002070002070002030000a62b000447941f00ee878352")!)
            let config = message.messageBlocks[0] as! VersionResponse
            XCTAssertEqual(29, config.data.count)
            XCTAssertEqual("2.7.0", String(describing: config.firmwareVersion))
            XCTAssertEqual("2.7.0", String(describing: config.iFirmwareVersion))
            XCTAssertEqual(42539, config.lot)
            XCTAssertEqual(280468, config.tid)
            XCTAssertEqual(0x1f00ee87, config.address)
            XCTAssertEqual(2, config.productId)
            XCTAssertEqual(.pairingCompleted, config.podProgressStatus)
            XCTAssertNil(config.rssi)
            XCTAssertNil(config.gain)
            XCTAssertEqual(Pod.pulseSize, config.pulseSize)
            XCTAssertEqual(Pod.secondsPerBolusPulse, config.secondsPerBolusPulse)
            XCTAssertEqual(Pod.secondsPerPrimePulse, config.secondsPerPrimePulse)
            XCTAssertEqual(Pod.primeUnits, config.primeUnits)
            XCTAssertEqual(Pod.cannulaInsertionUnits, config.cannulaInsertionUnits)
            XCTAssertEqual(Pod.serviceDuration, config.serviceDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testParsingShortDashVersionResponse() {
        do {
            let config = try VersionResponse(encodedData: Data(hexadecimalString: "0115031b0008080004020812a011000c175700ffffffff")!)
            XCTAssertEqual(23, config.data.count)
            XCTAssertEqual("3.27.0", String(describing: config.firmwareVersion))
            XCTAssertEqual("8.8.0", String(describing: config.iFirmwareVersion))
            XCTAssertEqual(135438353, config.lot)
            XCTAssertEqual(792407, config.tid)
            XCTAssertEqual(0xFFFFFFFF, config.address)
            XCTAssertEqual(4, config.productId)
            XCTAssertEqual(.reminderInitialized, config.podProgressStatus)
            XCTAssertEqual(0, config.gain)
            XCTAssertEqual(0, config.rssi)
            XCTAssertNil(config.pulseSize)
            XCTAssertNil(config.secondsPerBolusPulse)
            XCTAssertNil(config.secondsPerPrimePulse)
            XCTAssertNil(config.primeUnits)
            XCTAssertNil(config.cannulaInsertionUnits)
            XCTAssertNil(config.serviceDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testParsingLongDashVersionResponse() {
        do {
            let message = try Message(encodedData: Data(hexadecimalString: "ffffffff0c1d011b13881008340a50031b0008080004030812a011000c175717244389816c")!)
            let config = message.messageBlocks[0] as! VersionResponse
            XCTAssertEqual(29, config.data.count)
            XCTAssertEqual("3.27.0", String(describing: config.firmwareVersion))
            XCTAssertEqual("8.8.0", String(describing: config.iFirmwareVersion))
            XCTAssertEqual(135438353, config.lot)
            XCTAssertEqual(792407, config.tid)
            XCTAssertEqual(0x17244389, config.address)
            XCTAssertEqual(4, config.productId)
            XCTAssertEqual(.pairingCompleted, config.podProgressStatus)
            XCTAssertNil(config.rssi)
            XCTAssertNil(config.gain)
            XCTAssertEqual(Pod.pulseSize, config.pulseSize)
            XCTAssertEqual(Pod.secondsPerBolusPulse, config.secondsPerBolusPulse)
            XCTAssertEqual(Pod.secondsPerPrimePulse, config.secondsPerPrimePulse)
            XCTAssertEqual(Pod.primeUnits, config.primeUnits)
            XCTAssertEqual(Pod.cannulaInsertionUnits, config.cannulaInsertionUnits)
            XCTAssertEqual(Pod.serviceDuration, config.serviceDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testParsingConfigWithPairingExpired() {
        do {
            let message = try Message(encodedData: Data(hexadecimalString: "ffffffff04170115020700020700020e0000a5ad00053030971f08686301fd")!)
            let config = message.messageBlocks[0] as! VersionResponse
            XCTAssertEqual("2.7.0", String(describing: config.firmwareVersion))
            XCTAssertEqual("2.7.0", String(describing: config.iFirmwareVersion))
            XCTAssertEqual(0x0000a5ad, config.lot)
            XCTAssertEqual(0x00053030, config.tid)
            XCTAssertEqual(0x1f086863, config.address)
            XCTAssertEqual(2, config.productId)
            XCTAssertEqual(.activationTimeExceeded, config.podProgressStatus)
            XCTAssertEqual(2, config.gain)
            XCTAssertEqual(0x17, config.rssi)
            XCTAssertNil(config.pulseSize)
            XCTAssertNil(config.secondsPerBolusPulse)
            XCTAssertNil(config.secondsPerPrimePulse)
            XCTAssertNil(config.primeUnits)
            XCTAssertNil(config.cannulaInsertionUnits)
            XCTAssertNil(config.serviceDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testAssignAddressCommand() {
        do {
            // Encode
            let encoded = AssignAddressCommand(address: 0x1f01482a)
            XCTAssertEqual("07041f01482a", encoded.data.hexadecimalString)

            // Decode
            let decoded = try AssignAddressCommand(encodedData: Data(hexadecimalString: "07041f01482a")!)
            XCTAssertEqual(0x1f01482a, decoded.address)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testSetupPodCommand() {
        do {
            var components = DateComponents()
            components.day = 12
            components.month = 6
            components.year = 2016
            components.hour = 13
            components.minute = 47

            // Decode
            let decoded = try SetupPodCommand(encodedData: Data(hexadecimalString: "03131f0218c31404060c100d2f0000a4be0004e4a1")!)
            XCTAssertEqual(0x1f0218c3, decoded.address)
            XCTAssertEqual(components, decoded.dateComponents)
            XCTAssertEqual(0x0000a4be, decoded.lot)
            XCTAssertEqual(0x0004e4a1, decoded.tid)

            // Encode
            let encoded = SetupPodCommand(address: 0x1f0218c3, dateComponents: components, lot: 0x0000a4be, tid: 0x0004e4a1)
            XCTAssertEqual("03131f0218c31404060c100d2f0000a4be0004e4a1", encoded.data.hexadecimalString)            

        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPrime() {
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP 0ppp
            // 1a 0e bed2e16b 02 010a 01 01a0 0034 0034
            // Decode
            let cmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a0ebed2e16b02010a0101a000340034")!)
            XCTAssertEqual(0xbed2e16b, cmd.nonce)
            
            if case SetInsulinScheduleCommand.DeliverySchedule.bolus(let units, let timeBetweenPulses, let table) = cmd.deliverySchedule {
                XCTAssertEqual(Pod.primeUnits, units)
                XCTAssertEqual(Pod.secondsPerPrimePulse, timeBetweenPulses)
                XCTAssertEqual(1, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(Int(Pod.primeUnits / Pod.pulseSize), table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)

            } else {
                XCTFail("Expected ScheduleEntry.bolus type")
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testInsertCannula() {
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP 0ppp
            // 1a 0e 7e30bf16 02 0065 01 0050 000a 000a
            // Decode
            let cmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a0e7e30bf16020065010050000a000a")!)
            XCTAssertEqual(0x7e30bf16, cmd.nonce)

            if case SetInsulinScheduleCommand.DeliverySchedule.bolus(let units, let timeBetweenPulses, let table) = cmd.deliverySchedule {
                XCTAssertEqual(Pod.cannulaInsertionUnits, units)
                XCTAssertEqual(Pod.secondsPerPrimePulse, timeBetweenPulses)
                XCTAssertEqual(1, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(Int(Pod.cannulaInsertionUnits / Pod.pulseSize), table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
            } else {
                XCTFail("Expected ScheduleEntry.bolus type")
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testStatusResponseAlarmsParsing() {
        // 1d 28 0082 00 0044 46eb ff
        
        do {
            // Decode
            let status = try StatusResponse(encodedData: Data(hexadecimalString: "1d28008200004446ebff")!)
            XCTAssert(status.alerts.contains(.slot3))
            XCTAssert(status.alerts.contains(.slot7))
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testConfigureAlertsCommand() {
        // 79a4 10df 0502
        // Pod expires 1 minute short of 3 days
        let podSoftExpirationTime = TimeInterval(hours:72) - TimeInterval(minutes:1)
        let alertConfig1 = AlertConfiguration(alertType: .slot7, active: true, autoOffModifier: false, duration: .hours(7), trigger: .timeUntilAlert(podSoftExpirationTime), beepRepeat: .every60Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        XCTAssertEqual("79a410df0502", alertConfig1.data.hexadecimalString)

        // 2800 1283 0602
        let podHardExpirationTime = TimeInterval(hours:79) - TimeInterval(minutes:1)
        let alertConfig2 = AlertConfiguration(alertType: .slot2, active: true, autoOffModifier: false, duration: .minutes(0), trigger: .timeUntilAlert(podHardExpirationTime), beepRepeat: .every15Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        XCTAssertEqual("280012830602", alertConfig2.data.hexadecimalString)

        // 020f 0000 0202
        let alertConfig3 = AlertConfiguration(alertType: .slot0, active: false, autoOffModifier: true, duration: .minutes(15), trigger: .timeUntilAlert(0), beepRepeat: .every1MinuteFor15Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        XCTAssertEqual("020f00000202", alertConfig3.data.hexadecimalString)
        
        let configureAlerts = ConfigureAlertsCommand(nonce: 0xfeb6268b, configurations:[alertConfig1, alertConfig2, alertConfig3])
        XCTAssertEqual("1916feb6268b79a410df0502280012830602020f00000202", configureAlerts.data.hexadecimalString)
        
        do {
            let decoded = try ConfigureAlertsCommand(encodedData: Data(hexadecimalString: "1916feb6268b79a410df0502280012830602020f00000202")!)
            XCTAssertEqual(3, decoded.configurations.count)
            
            let config1 = decoded.configurations[0]
            XCTAssertEqual(.slot7, config1.slot)
            XCTAssertEqual(true, config1.active)
            XCTAssertEqual(false, config1.autoOffModifier)
            XCTAssertEqual(.hours(7), config1.duration)
            if case AlertTrigger.timeUntilAlert(let duration) = config1.trigger {
                XCTAssertEqual(podSoftExpirationTime, duration)
            }
            XCTAssertEqual(.every60Minutes, config1.beepRepeat)
            XCTAssertEqual(.bipBeepBipBeepBipBeepBipBeep, config1.beepType)
            
            let cfg = try AlertConfiguration(encodedData: Data(hexadecimalString: "4c0000640102")!)
            XCTAssertEqual(.slot4, cfg.slot)
            XCTAssertEqual(true, cfg.active)
            XCTAssertEqual(false, cfg.autoOffModifier)
            XCTAssertEqual(0, cfg.duration)
            if case AlertTrigger.unitsRemaining(let volume) = cfg.trigger {
                XCTAssertEqual(10, volume)
            }
            XCTAssertEqual(.every1MinuteFor3MinutesAndRepeatEvery60Minutes, cfg.beepRepeat)
            XCTAssertEqual(.bipBeepBipBeepBipBeepBipBeep, cfg.beepType)


        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
}

