//
//  RemoteDataManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutKit


class RemoteDataManager {

    var NightscoutClient: NightscoutClient? {
        return nightscoutService.uploader
    }

    var nightscoutService: NightscoutService {
        didSet {
            keychain.setNightscoutURL(nightscoutService.siteURL, secret: nightscoutService.APISecret)
        }
    }

    private let keychain = KeychainManager()

    init() {
        // Migrate config setttings to the Keychain

        if let (siteURL, APISecret) = keychain.getNightscoutCredentials() {
            nightscoutService = NightscoutService(siteURL: siteURL, APISecret: APISecret)
        } else if let siteURL = Config.sharedInstance().nightscoutURL,
            let APISecret = Config.sharedInstance().nightscoutAPISecret
        {
            keychain.setNightscoutURL(siteURL, secret: APISecret)
            nightscoutService = NightscoutService(siteURL: siteURL, APISecret: APISecret)
        } else {
            nightscoutService = NightscoutService(siteURL: nil, APISecret: nil)
        }
        
    }

}
