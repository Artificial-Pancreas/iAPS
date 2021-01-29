//
//  JSON.swift
//  FreeAPS
//
//  Created by Ivan Valkou on 19.01.2021.
//

import Foundation


protocol JSON: Codable {
    func toString() -> String
    init?(from: String)
}

extension JSON {
    func toString() -> String {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }

    init?(from: String) {
        guard let data = from.data(using: .utf8),
            let object = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = object
    }
}
