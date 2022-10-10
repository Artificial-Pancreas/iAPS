//
//  ReconciliationTests.swift
//  MinimedKitTests
//
//  Created by Pete Schwamb on 9/5/22.
//  Copyright © 2022 Pete Schwamb. All rights reserved.
//

import XCTest
import RileyLinkBLEKit
@testable import MinimedKit
import LoopKit

extension DateFormatter {
    static var descriptionFormatter: DateFormatter {
        let formatter = self.init()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"

        return formatter
    }
}


final class ReconciliationTests: XCTestCase {

    let testingDateFormatter = DateFormatter.descriptionFormatter

    func testingDate(_ input: String) -> Date {
        return testingDateFormatter.date(from: input)!
    }

    func testPendingDoseUpdatesWithActualDeliveryFromHistoryDose() {

        let bolusTime = Date().addingTimeInterval(-TimeInterval(minutes: 5));

        let bolusEventTime = bolusTime.addingTimeInterval(2)

        let cancelTime = bolusEventTime.addingTimeInterval(TimeInterval(minutes: 1))

        let unfinalizedBolus = UnfinalizedDose(bolusAmount: 5.4, startTime: bolusTime, duration: TimeInterval(200), insulinType: .novolog, automatic: false, isReconciledWithHistory: false)

        // 5.4 bolus interrupted at 1.0 units
        let eventDose = DoseEntry(type: .bolus, startDate: bolusEventTime, endDate: cancelTime, value: unfinalizedBolus.units, unit: .units, deliveredUnits: 1.0)

        let bolusEvent = NewPumpEvent(
            date: bolusEventTime,
            dose: eventDose,
            raw: Data(hexadecimalString: "abcdef")!,
            title: "Test Bolus",
            type: .bolus)

        let result = MinimedPumpManager.reconcilePendingDosesWith([bolusEvent], reconciliationMappings: [:], pendingDoses: [unfinalizedBolus])

        // Should mark pending bolus as reconciled
        XCTAssertEqual(1, result.pendingDoses.count)
        let pendingBolus = result.pendingDoses.first!
        XCTAssertEqual(true, pendingBolus.isReconciledWithHistory)

        // Pending bolus should be updated with actual delivery amount
        XCTAssertEqual(1.0, pendingBolus.units)
        XCTAssertEqual(5.4, pendingBolus.programmedUnits)
        XCTAssertEqual(TimeInterval(minutes: 1), pendingBolus.duration)
        XCTAssertEqual(true, pendingBolus.isFinished)
    }

    func testReconciledDosesShouldOnlyAppearInReturnedPendingDoses() {

        let bolusTime = Date().addingTimeInterval(-TimeInterval(minutes: 5));

        // Shows up in history 2 seconds later
        let bolusEventTime = bolusTime.addingTimeInterval(2)

        let bolusAmount = 1.5

        let bolusDuration = PumpModel.model523.bolusDeliveryTime(units: bolusAmount)

        let unfinalizedBolus = UnfinalizedDose(bolusAmount: bolusAmount, startTime: bolusTime, duration: bolusDuration, insulinType: .novolog, automatic: false, isReconciledWithHistory: false)

        let eventDose = DoseEntry(type: .bolus, startDate: bolusEventTime, endDate: bolusEventTime.addingTimeInterval(bolusDuration), value: bolusAmount, unit: .units, deliveredUnits: bolusAmount)

        let bolusEvent = NewPumpEvent(
            date: bolusEventTime,
            dose: eventDose,
            raw: Data(hexadecimalString: "abcdef")!,
            title: "Test Bolus",
            type: .bolus)

        let result = MinimedPumpManager.reconcilePendingDosesWith([bolusEvent], reconciliationMappings: [:], pendingDoses: [unfinalizedBolus])

        // Should mark pending bolus as reconciled
        XCTAssertEqual(1, result.pendingDoses.count)
        let pendingBolus = result.pendingDoses.first!
        XCTAssertEqual(true, pendingBolus.isReconciledWithHistory)

        XCTAssertEqual(1, result.reconciliationMappings.count)
        XCTAssertEqual(unfinalizedBolus.uuid, result.reconciliationMappings[bolusEvent.raw]?.uuid)
        XCTAssertEqual(unfinalizedBolus.startTime, result.reconciliationMappings[bolusEvent.raw]?.startTime)

        // Bolus should not be returned as history event
        XCTAssert(result.remainingEvents.isEmpty)
    }

    func testReconciledDosesShouldNotAppearInReturnedPumpEvents() {

        let bolusTime = Date().addingTimeInterval(-TimeInterval(minutes: 5));

        // Shows up in history 2 seconds later
        let bolusEventTime = bolusTime.addingTimeInterval(2)

        let bolusAmount = 1.5

        let bolusDuration = PumpModel.model523.bolusDeliveryTime(units: bolusAmount)

        let eventDose = DoseEntry(type: .bolus, startDate: bolusEventTime, endDate: bolusEventTime.addingTimeInterval(bolusDuration), value: bolusAmount, unit: .units, deliveredUnits: bolusAmount)

        let bolusEvent = NewPumpEvent(
            date: bolusEventTime,
            dose: eventDose,
            raw: Data(hexadecimalString: "abcdef")!,
            title: "Test Bolus",
            type: .bolus)



        let reconciliationMappings: [Data:ReconciledDoseMapping] = [
            bolusEvent.raw : ReconciledDoseMapping(startTime: bolusTime, uuid: UUID(), eventRaw: bolusEvent.raw)
        ]

        let result = MinimedPumpManager.reconcilePendingDosesWith([bolusEvent], reconciliationMappings: reconciliationMappings, pendingDoses: [])

        // Bolus should not be returned as history event
        XCTAssert(result.remainingEvents.isEmpty)
    }
}
