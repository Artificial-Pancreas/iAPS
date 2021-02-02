//
//  MealInputs.swift
//  FreeAPS
//
//  Created by Ivan Valkou on 02.02.2021.
//

import Foundation

struct MealInputs: JSON {
    let history: String
    let profile: String
    let basalprofile: String
    let clock: String
    let carbs: String
    let glucose: String
}
