//
//  GlucoseSettingsView.swift
//  LibreTransmitterUI
//
//  Created by Bjørn Inge Berg on 26/05/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import SwiftUI
import Combine
import HealthKit

struct GlucoseSettingsView: View {


    @State private var presentableStatus: StatusMessage?


    private var glucoseUnit: HKUnit

    public init(glucoseUnit: HKUnit) {
        if let savedGlucoseUnit = UserDefaults.standard.mmGlucoseUnit {
            self.glucoseUnit = savedGlucoseUnit
        } else {
            self.glucoseUnit = glucoseUnit
            UserDefaults.standard.mmGlucoseUnit = glucoseUnit
        }



    }

    @AppStorage("no.bjorninge.mmBackfillFromHistory") var mmBackfillFromHistory: Bool = true
    @AppStorage("no.bjorninge.mmBackfillFromTrend") var mmBackfillFromTrend: Bool = false
    @AppStorage("no.bjorninge.shouldPersistSensorData") var shouldPersistSensorData: Bool = false



    var body: some View {
        List {
            
            Section(header: Text("Backfill options"), footer:Text("Backfilling from trend is currently not well supported by Loop") ) {
                Toggle("Backfill from history", isOn:$mmBackfillFromHistory)
                Toggle("Backfill from trend", isOn: $mmBackfillFromTrend)
            }

            Section(header: Text("Debug options"), footer: Text("Adds a lot of data to the Issue Report ")) {
                Toggle("Persist sensordata", isOn:$shouldPersistSensorData)
            }

        }
        .listStyle(InsetGroupedListStyle())
        .alert(item: $presentableStatus) { status in
            Alert(title: Text(status.title), message: Text(status.message) , dismissButton: .default(Text("Got it!")))
        }
        .navigationBarTitle("Glucose Settings")

    }




}


struct GlucoseSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GlucoseSettingsView(glucoseUnit: HKUnit.millimolesPerLiter)
    }
}
