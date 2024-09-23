//
//  DanaKitRefillReservoirCannulaViewModel.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 23/09/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

class DanaKitRefillReservoirCannulaViewModel: ObservableObject {
    @Published var cannulaOnly: Bool
    
    init(cannulaOnly: Bool) {
        self.cannulaOnly = cannulaOnly
    }
}
