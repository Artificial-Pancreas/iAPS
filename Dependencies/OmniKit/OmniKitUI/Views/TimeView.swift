//
//  TimeView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 5/10/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct TimeView: View {
    
    let timeZone: TimeZone
    
    private let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    @State var currentDate = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var timeZoneString: String {
        shortTimeFormatter.timeZone = timeZone
        return shortTimeFormatter.string(from: currentDate)
    }

    var body: some View {
        Text(timeZoneString).onReceive(timer) { input in
           currentDate = input
        }
    }
}

struct TimeView_Previews: PreviewProvider {
    static var previews: some View {
        TimeView(timeZone: .current)
    }
}
