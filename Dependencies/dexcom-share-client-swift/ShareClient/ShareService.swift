//
//  ShareService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


// Encapsulates the Dexcom Share client service and its authentication
public class ShareService: ServiceAuthentication {
    public var credentialValues: [String?]

    public let title: String = LocalizedString("Dexcom Share", comment: "The title of the Dexcom Share service")

    public init(username: String?, password: String?, url: URL?) {
        credentialValues = [
            username,
            password,
            url?.absoluteString
        ]

        /*
         To enable Loop to use a custom share server, change the value of customServer 
         and remove the comment markers on line 55 and 62.

         You can find installation instructions for one such custom share server at
         https://github.com/dabear/NightscoutShareServer
         */

        /*
        let customServer = "https://REPLACEME"
        let customServerTitle = "Custom"

        credentials[2].options?.append(
                (title: LocalizedString(customServerTitle, comment: "Custom share server option title"),
                value: customServer))
        */

        if let username = username, let password = password, let url = url {
            isAuthorized = true
            client = ShareClient(username: username, password: password, shareServer: url.absoluteString)
        }
    }

    // The share client, if credentials are present
    private(set) var client: ShareClient?

    public var username: String? {
        return credentialValues[0]
    }

    var password: String? {
        return credentialValues[1]
    }

    var url: URL? {
        guard let urlString = credentialValues[2] else {
            return nil
        }

        return URL(string: urlString)
    }

    public var isAuthorized: Bool = false

    public func verify(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        guard let username = username, let password = password, let url = url else {
            completion(false, nil)
            return
        }

        let client = ShareClient(username: username, password: password, shareServer: url.absoluteString)
        client.fetchLast(1) { (error, _) in
            completion(error == nil, error)
        }
        self.client = client
    }

    public func reset() {
        isAuthorized = false
        client = nil
    }
}


private let DexcomShareURL = URL(string: KnownShareServers.US.rawValue)!
private let DexcomShareServiceLabel = "DexcomShare2"


extension KeychainManager {
    func setDexcomShareUsername(_ username: String?, password: String?, url: URL?) throws {
        let credentials: InternetCredentials?

        if let username = username, let password = password, let url = url {
            credentials = InternetCredentials(username: username, password: password, url: url)
        } else {
            credentials = nil
        }

        // Replace the legacy URL-keyed credentials
        try replaceInternetCredentials(nil, forURL: DexcomShareURL)

        try replaceInternetCredentials(credentials, forLabel: DexcomShareServiceLabel)
    }

    func getDexcomShareCredentials() -> (username: String, password: String, url: URL)? {
        do { // Silence all errors and return nil
            do {
                let credentials = try getInternetCredentials(label: DexcomShareServiceLabel)

                return (username: credentials.username, password: credentials.password, url: credentials.url)
            } catch KeychainManagerError.copy {
                // Fetch and replace the legacy URL-keyed credentials
                let credentials = try getInternetCredentials(url: DexcomShareURL)

                try setDexcomShareUsername(credentials.username, password: credentials.password, url: credentials.url)

                return (username: credentials.username, password: credentials.password, url: credentials.url)
            }
        } catch {
            return nil
        }
    }
}


extension ShareService {
    public convenience init(keychainManager: KeychainManager = KeychainManager()) {
        if let (username, password, url) = keychainManager.getDexcomShareCredentials() {
            self.init(username: username, password: password, url: url)
        } else {
            self.init(username: nil, password: nil, url: nil)
        }
    }
}
