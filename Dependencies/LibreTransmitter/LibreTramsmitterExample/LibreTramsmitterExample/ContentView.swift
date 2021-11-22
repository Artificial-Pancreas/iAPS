//
//  ContentView.swift
//  LibreTramsmitterExample
//
//  Created by Ivan Valkou on 29.10.2021.
//

import SwiftUI
import LibreTransmitter
import HealthKit

struct ContentView: View {
    @StateObject var state = StateModel()

    @State var manager: LibreTransmitterManager? {
        didSet {
            manager?.cgmManagerDelegate = state
        }
    }

    @State var setupPresented = false
    @State var settingsPresented = false
    @AppStorage("LibreTransmitterManager.configured") var configured = false

    let unit = HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())

    var body: some View {
        VStack(spacing: 50) {
            Text("\(state.currentGlucose?.glucoseDouble ?? .nan)")
            Text("\(state.trend.symbol)")

            Button("Libre Transmitter") {
                setupPresented = true
            }

            Button("Test alert sound") {
                NotificationHelper.playSoundIfNeeded()
            }
        }
        .sheet(isPresented: $setupPresented) {} content: {
            if configured, let manager = manager {
                LibreTransmitterSettingsView(
                    manager: manager,
                    glucoseUnit: unit) {
                        self.manager = nil
                        configured = false
                    } completion: {
                        setupPresented = false
                    }

            } else {
                LibreTransmitterSetupView { manager in
                    self.manager = manager
                    configured = true
                } completion: {
                    setupPresented = false
                }
            }
        }
        .onAppear {
            if configured {
                manager = LibreTransmitterManager()
            }
        }
    }
}
