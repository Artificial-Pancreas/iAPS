//
//  TestView.swift
//  MiaomiaoClientUI
//
//  Created by Bjørn Inge Berg on 15/10/2020.
//  Copyright © 2020 Bjørn Inge Vikhammermo Berg. All rights reserved.
//

import SwiftUI

struct SnoozeView: View {

    var pickerTimes: [TimeInterval] = ({
        pickerTimesArray()

    })()

    var formatter : DateComponentsFormatter = ({
        var f = DateComponentsFormatter()
        f.allowsFractionalUnits = false
        f.unitsStyle = .full
        return f

    })()

    func formatInterval(_ interval: TimeInterval) -> String {
        formatter.string(from: interval)!
    }



    @Binding var isAlarming : Bool
    @Binding var activeAlarms: LibreTransmitter.GlucoseScheduleAlarmResult


    static func pickerTimesArray() -> [TimeInterval] {
        var arr  = [TimeInterval]()

        let mins10 = 0.166_67
        let mins20 = mins10 * 2
        let mins30 = mins10 * 3
        //let mins40 = mins10 * 4

        for hr in 0..<2 {
            for min in [0.0, mins20, mins20 * 2] {
                arr.append(TimeInterval(hours: Double(hr) + min))
            }
        }
        for hr in 2..<4 {
            for min in [0.0, mins30] {
                arr.append(TimeInterval(hours: Double(hr) + min))
            }
        }

        for hr in 4...8 {
            arr.append(TimeInterval(hours: Double(hr)))
        }

        return arr
    }

    func getSnoozeDescription() -> String {
        var snoozeDescription  = ""
        var celltext = ""

        switch activeAlarms {
            case .high:
                celltext = NSLocalizedString("High Glucose Alarm active", comment: "High Glucose Alarm active")
            case .low:
                celltext = NSLocalizedString("Low Glucose Alarm active", comment: "Low Glucose Alarm active")
            case .none:
                celltext = NSLocalizedString("No Glucose Alarm active", comment: "No Glucose Alarm active")
        }

        if let until = GlucoseScheduleList.snoozedUntil {
            snoozeDescription = String(format: NSLocalizedString("snoozing until %@", comment: "snoozing until %@"), until.description(with: .current))
        } else {
            snoozeDescription = NSLocalizedString("not snoozing", comment: "not snoozing")  
        }

        return [celltext, snoozeDescription].joined(separator: ", ")
    }

    @State private var selectedInterval = 0
    @State private var snoozeDescription = "nothing to see here"

    var snoozeButton: some View {
        VStack(alignment: .leading) {
            Button(action: {
                print("snooze from testview clicked")
                let interval = pickerTimes[selectedInterval]
                let snoozeFor = formatter.string(from: interval)!
                let untilDate = Date() + interval
                UserDefaults.standard.snoozedUntil = untilDate < Date() ? nil : untilDate
                print("will snooze for \(snoozeFor) until \(untilDate.description(with: .current))")
                snoozeDescription = getSnoozeDescription()
            }) {
                Text("Click to Snooze Alerts")
                    .padding()
            }
        }

    }

    var snoozePicker: some View {
        VStack {
            Picker(selection: $selectedInterval, label: Text("Strength")) {
                ForEach(0 ..< pickerTimes.count) {
                    Text(formatInterval(self.pickerTimes[$0]))
                }
            }
            .pickerStyle(.wheel)
        }

    }

    var snoozeDesc : some View {
        VStack(alignment: .leading) {
            Text(snoozeDescription)
        }
    }

    var body: some View {
        Form {
            snoozeDesc
            snoozePicker
            snoozeButton
        }
        .onAppear {
            snoozeDescription = getSnoozeDescription()
        }
    }
}

struct TestView_Previews: PreviewProvider {
    static var previews: some View {
        SnoozeView(isAlarming: .constant(true), activeAlarms: .constant(.none))
    }
}
