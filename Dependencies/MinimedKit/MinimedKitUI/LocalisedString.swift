//
//  LocalisedString.swift
//  MinimedKit
//
//  Created by Pete Schwamb on 3/19/23.
//

import Foundation

private class LocalBundle {
    /// Returns the resource bundle associated with the current Swift module.
    static var main: Bundle = {
        if let mainResourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: mainResourceURL.appendingPathComponent("MinimedKitUI_MinimedKitUI.bundle"))
        {
            return bundle
        }
        return Bundle(for: LocalBundle.self)
    }()
}

func LocalizedString(_ key: String, tableName: String? = nil, value: String? = nil, comment: String) -> String {
    if let value = value {
        return NSLocalizedString(key, tableName: tableName, bundle: LocalBundle.main, value: value, comment: comment)
    } else {
        return NSLocalizedString(key, tableName: tableName, bundle: LocalBundle.main, comment: comment)
    }
}
