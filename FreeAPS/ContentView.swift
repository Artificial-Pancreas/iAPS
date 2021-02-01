//
//  ContentView.swift
//  FreeAPS
//
//  Created by Ivan Valkou on 12.01.2021.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
            .onAppear {
                OpenAPS().meal()
//                OpenAPS().determineBasal()
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
