//
//  main.swift
//  OmniBLEParser
//
//  Based on OmniKitPacketParser/main.swift
//  Created by Joseph Moran on 02/02/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

// These options can be forced off by using the -q option argument
fileprivate var printDate: Bool = true // whether to print the date (when available) along with the time
fileprivate var printFullMessage: Bool = true // whether to print full message decode including the address and seq

//from NSHipster - http://nshipster.com/swift-literal-convertible/
struct Regex {
    let pattern: String
    let options: NSRegularExpression.Options!
    
    private var matcher: NSRegularExpression {
        return try! NSRegularExpression(pattern: self.pattern, options: self.options)
    }
    
    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        self.pattern = pattern
        self.options = options
    }
    
    func match(string: String, options: NSRegularExpression.MatchingOptions = []) -> Bool {
        return self.matcher.numberOfMatches(in: string, options: options, range: NSMakeRange(0, string.count)) != 0
    }
}

protocol RegularExpressionMatchable {
    func match(regex: Regex) -> Bool
}

extension String: RegularExpressionMatchable {
    func match(regex: Regex) -> Bool {
        return regex.match(string: self)
    }
}

func ~=<T: RegularExpressionMatchable>(pattern: Regex, matchable: T) -> Bool {
    return matchable.match(regex: pattern)
}

func printDecoded(timeStr: String, hexString: String)
{
    if let data = Data(hexadecimalString: hexString) {
        do {
            let message = try Message(encodedData: data, checkCRC: false)
            let omnipodMessage = message.messageBlocks[0].blockType
            let type: String
            if omnipodMessage == .statusResponse || omnipodMessage == .podInfoResponse || omnipodMessage == .versionResponse || omnipodMessage == .errorResponse {
                type = "RESPONSE: "
            } else {
                type = "COMMAND:  "
            }
            if printFullMessage {
                // print the complete message with the address and seq
                print("\(type)\(timeStr) \(message)")
            } else {
                // skip printing the address and seq for each message
                print("\(type)\(timeStr) \(message.messageBlocks)")
            }
        } catch let error {
            print("Could not parse \(hexString): \(error)")
        }
    }
}

// * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD send 17cae1dd00030e010003b1
// * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD receive 17cae1dd040a1d18002ab00000019fff0198
func parseLoopReportLine(_ line: String) {
    let components = line.components(separatedBy: .whitespaces)
    let hexString = components[components.count - 1]

    let date = components[1]
    let time = components[2]
    let timeStr = printDate ? date + " " + time : time

    printDecoded(timeStr: timeStr, hexString: hexString)
}

// 2023-02-02 15:23:13.094289-0800 Loop[60606:22880823] [PodMessageTransport] Send(Hex): 1776c2c63c030e010000a0
// 2023-02-02 15:23:13.497849-0800 Loop[60606:22880823] [PodMessageTransport] Recv(Hex): 1776c2c6000a1d180064d800000443ff0000
func parseXcodeLogLine(_ line: String) {
    let components = line.components(separatedBy: .whitespaces)
    let hexString = components[components.count - 1]

    let date = components[0]
    let time = components[1].padding(toLength: 15, withPad: " ", startingAt: 0)  // skip the -0000 portion
    let timeStr = printDate ? date + " " + time : time

    printDecoded(timeStr: timeStr, hexString: hexString)
}

// N.B. Simulator output typically has a space after the hex string!
// INFO[7699] pkg command; 0x0e; GET_STATUS; HEX, 1776c2c63c030e010000a0
// INFO[7699] pkg response 0x1d; HEX, 1776c2c6000a1d280064e80000057bff0000
// INFO[2023-09-04T18:17:06-07:00] pkg command; 0x07; GET_VERSION; HEX, ffffffff00060704ffffffff82b2
// INFO[2023-09-04T18:17:06-07:00] pkg response 0x1; HEX, ffffffff04170115040a00010300040208146db10006e45100ffffffff0000
func parseSimulatorLogLine(_ line: String) {
    let components = line.components(separatedBy: .whitespaces)
    var hexStringIndex = components.count - 1
    let hexString: String
    if components[hexStringIndex].isEmpty {
        hexStringIndex -= 1 // back up to handle a trailing space
    }
    hexString = components[hexStringIndex]

    let c0 = components[0]
    // start at 5 for printDate or shorter "INFO[7699]" format
    let offset = printDate || c0.count <= 16 ? 5 : 16
    let startIndex = c0.index(c0.startIndex, offsetBy: offset)
    let endIndex = c0.index(c0.startIndex, offsetBy: c0.count - 2)
    let timeStr = String(c0[startIndex...endIndex])

    printDecoded(timeStr: timeStr, hexString: hexString)
}

// 2023-09-02T00:29:04-0700 [DeviceManager] DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 563 - DEV: Device message: 17b3931b08030e01008205
// 2023-09-02T00:29:04-0700 [DeviceManager] DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 563 - DEV: Device message: 17b3931b0c0a1d1800b48000000683ff017d
func parseIAPSLogLine(_ line: String) {
    let components = line.components(separatedBy: .whitespaces)
    let hexString = components[components.count - 1]

    let c0 = components[0]
    let offset = printDate ? 0 : 12
    let startIndex = c0.index(c0.startIndex, offsetBy: offset)
    let endIndex = c0.index(c0.startIndex, offsetBy: c0.count - 1)
    let timeStr = String(c0[startIndex...endIndex])

    printDecoded(timeStr: timeStr, hexString: hexString)
}

func usage() {
    print("Usage: [-q] file...")
    print("Set the Xcode Arguments Passed on Launch using Product->Scheme->Edit Scheme...")
    print("to specify the full path to Loop Report, Xcode, sim or iAPS log file(s) to parse.\n")
    exit(1)
}

if CommandLine.argc <= 1 {
    usage()
}

for arg in CommandLine.arguments[1...] {
    if arg == "-q" {
        printDate = false
        printFullMessage = false
        continue
    } else if arg.starts(with: "-") {
        // no other arguments curently supported
        usage()
    }

    print("\nParsing \(arg)")
    do {
        let data = try String(contentsOfFile: arg, encoding: .utf8)
        let lines = data.components(separatedBy: .newlines)

        for line in lines {
            switch line {
            // * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD send 17cae1dd00030e010003b1
            // * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD receive 17cae1dd040a1d18002ab00000019fff0198
            case Regex("(send|receive) [0-9a-fA-F]+$"):
                parseLoopReportLine(line)

            // 2023-02-02 15:23:13.094289-0800 Loop[60606:22880823] [PodMessageTransport] Send(Hex): 1776c2c63c030e010000a0
            // 2023-02-02 15:23:13.497849-0800 Loop[60606:22880823] [PodMessageTransport] Recv(Hex): 1776c2c6000a1d180064d800000443ff0000
            case Regex("(Send|Recv)\\(Hex\\): [0-9a-fA-F]+$"):
                parseXcodeLogLine(line)

            // INFO[7699] pkg command; 0x0e; GET_STATUS; HEX, 1776c2c63c030e010000a0
            // INFO[7699] pkg response 0x1d; HEX, 1776c2c6000a1d280064e80000057bff0000
            // N.B., Simulator log files typically have a trailing space!
            case Regex("; HEX, [0-9a-fA-F]+ $"), Regex("; HEX, [0-9a-fA-F]+$"):
                parseSimulatorLogLine(line)

            // 2023-09-02T00:29:04-0700 [DeviceManager] DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 563 - DEV: Device message: 17b3931b08030e01008205
            // 2023-09-02T00:29:04-0700 [DeviceManager] DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 563 - DEV: Device message: 17b3931b0c0a1d1800b48000000683ff017d
            case Regex("Device message: [0-9a-fA-F]+$"):
                // Don't mistakenly match an iaps xcode log file line as an iaps log file line
                // 2023-10-28 22:37:24.584982-0700 FreeAPS[6030:4151040] [DeviceManager] DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 563 DEV: Device message: 17eed3be3824191c494e532e2800069406024c0001f4010268000000060279a404f005021e040300000001ca
                if !line.contains(" FreeAPS") {
                    parseIAPSLogLine(line)
                }

            default:
                break
            }
        }
    } catch let error {
        print("Error: \(error)")
    }
    print("\n")
}
