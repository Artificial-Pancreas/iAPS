//
//  DanaKitRefillReservoirCannula.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 23/09/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI

struct DanaKitRefillReservoirView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @ObservedObject var viewModel: DanaKitRefillReservoirCannulaViewModel

    
    var body: some View {
        List {
            
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .navigationBarTitle(LocalizedString(viewModel.cannulaOnly ? "Cannula refill" : "Reservoir/cannula refill", comment: "Title for reservoir/cannula refill"))
    }
}

struct DanaKitRefillCannulaView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @ObservedObject var viewModel: DanaKitRefillReservoirCannulaViewModel

    
    var body: some View {
        VStack(alignment: .leading) {
            
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .navigationBarTitle(LocalizedString(viewModel.cannulaOnly ? "Cannula refill" : "Reservoir/cannula refill", comment: "Title for reservoir/cannula refill"))
    }
}
