//
//  StateModel.swift
//  LibreTramsmitterExample
//
//  Created by Ivan Valkou on 09.11.2021.
//

import SwiftUI
import LibreTransmitter

final class StateModel: ObservableObject {
    private let delegateQueue = DispatchQueue(label: "StateModel.delegateQueue")
    @Published var currentGlucose: LibreGlucose?
    @Published var trend: GlucoseTrend = .flat
}

extension StateModel: LibreTransmitterManagerDelegate {
    var queue: DispatchQueue {
        delegateQueue
    }

    func startDateToFilterNewData(for: LibreTransmitterManager) -> Date? {
        Date().addingTimeInterval(-3600)
    }

    func cgmManager(_ manager: LibreTransmitterManager, hasNew result: Result<[LibreGlucose], Error>) {
        switch result {

        case let .success(data):
            print("New data: \(data)")
            DispatchQueue.main.async {
                self.trend = manager.glucoseDisplay?.trendType ?? .flat
                self.currentGlucose = data.first
            }
        case let .failure(error):
            print("Error: \(error.localizedDescription)")
        }
    }

    func overcalibration(for: LibreTransmitterManager) -> ((Double) -> (Double))? {
        nil
    }
}
