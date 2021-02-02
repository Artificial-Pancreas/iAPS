//
//  Script.swift
//  FreeAPS
//
//  Created by Ivan Valkou on 29.01.2021.
//

import Foundation

struct Script {
    let name: String
    let body: String

    init(name: String) {
        self.name = name
        self.body = try! String(contentsOf: Bundle.main.url(forResource: "javascript/\(name)", withExtension: "js")!)
    }
}
