//
//  UIApplication+metadata.swift
//  MiaomiaoClient
//
//  Created by Bjørn Inge Berg on 30/12/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//

import Foundation

private let prefix = "no-bjorninge-mm"
enum AppMetaData {
    static var allProperties: String {
        Bundle.module.infoDictionary?.compactMap {
            $0.key.starts(with: prefix) ? "\($0.key): \($0.value)" : nil
        }.joined(separator: "\n") ?? "none"
    }
}
