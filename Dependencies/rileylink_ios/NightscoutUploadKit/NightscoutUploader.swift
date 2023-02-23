//
//  NightscoutUploader.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/9/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

public enum UploadError: LocalizedError {
    case httpError(status: Int, body: String)
    case missingTimezone
    case invalidResponse(reason: String)
    case unauthorized
    case missingConfiguration
    case invalidParameters
    case unexpectedResult(description: String)
    
    public var errorDescription: String? {
        switch self {
        case .httpError(let status, let body):
            return String(["HTTP Error", "Status Code: \(status)" ,"body: body: \(body)"].joined( separator: "\n"))
        case .missingTimezone:
            return "Missing Timezone"
        case .invalidResponse(let reason):
            return "Invalid Response: \(reason)"
        case .unauthorized:
            return "Unauthorized"
        case .missingConfiguration:
            return "Missing Nightscout Credentials"
        case .invalidParameters:
            return "Invalid parameters"
        case .unexpectedResult(let description):
            return "Unexpected Result: \(description)"
        }
    }
}

private enum Endpoint: String {
    case entries = "/api/v1/entries"
    case treatments = "/api/v1/treatments"
    case deviceStatus = "/api/v1/devicestatus"
    case authTest = "/api/v1/experiments/test"
    case profile = "/api/v1/profile"
    case currentProfile = "/api/v1/profile/current"
    case notifications = "/api/v2/notifications/loop"
}

public class NightscoutUploader {

    public var siteURL: URL
    public var apiSecret: String
    
    private(set) var entries = [GlucoseEntry]()
    private(set) var deviceStatuses = [[String: Any]]()
    private(set) var treatmentsQueue = [NightscoutTreatment]()

    private(set) var lastMeterMessageRxTime: Date?

    public var errorHandler: ((_ error: Error, _ context: String) -> Void)?

    private var dataAccessQueue: DispatchQueue = DispatchQueue(label: "com.rileylink.NightscoutUploadKit.dataAccessQueue", qos: .utility)

    public init(siteURL: URL, APISecret: String) {
        self.siteURL = siteURL
        self.apiSecret = APISecret
    }

    private func url(with path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = siteURL.scheme
        components.host = siteURL.host
        components.port = siteURL.port
        components.queryItems = queryItems
        components.path = path
        return components.url
    }

    private func url(for endpoint: Endpoint, queryItems: [URLQueryItem]? = nil) -> URL? {
        return url(with: endpoint.rawValue, queryItems: queryItems)
    }

    /// Attempts to upload nightscout treatment objects.
    /// This method will not retry if the network task failed.
    ///
    /// - parameter treatments:           An array of nightscout treatments.
    /// - parameter completionHandler:    A closure to execute when the task completes. It has a single argument for any error that might have occurred during the upload.
    public func upload(_ treatments: [NightscoutTreatment], completionHandler: @escaping (Result<[String],Error>) -> Void) {
        guard let url = url(for: .treatments) else {
            completionHandler(.failure(UploadError.missingConfiguration))
            return
        }
        postToNS(treatments.map { $0.dictionaryRepresentation }, url: url, completion: completionHandler)
    }

    /// Attempts to modify nightscout treatments. This method will not retry if the network task failed.
    ///
    /// - parameter treatments:        An array of nightscout treatments. The id attribute must be set, identifying the treatment to update.  Treatments without id will be ignored.
    /// - parameter completionHandler: A closure to execute when the task completes. It has a single argument for any error that might have occurred during the modify.
    public func modifyTreatments(_ treatments:[NightscoutTreatment], completionHandler: @escaping (Error?) -> Void) {
        guard let url = url(for: .treatments) else {
            completionHandler(UploadError.missingConfiguration)
            return
        }
        dataAccessQueue.async {
            let modifyGroup = DispatchGroup()
            var errors = [Error]()

            for treatment in treatments {
                guard treatment.id != nil, treatment.id != "NA" else {
                    continue
                }
                modifyGroup.enter()
                self.putToNS( treatment.dictionaryRepresentation, url: url ) { (error) in
                    if let error = error {
                        errors.append(error)
                    }
                    modifyGroup.leave()
                }
            }

            _ = modifyGroup.wait(timeout: DispatchTime.distantFuture)
            completionHandler(errors.first)
        }

    }

    /// Attempts to delete treatments from nightscout. This method will not retry if the network task failed.
    ///
    /// - parameter id:                An array of nightscout treatment ids
    /// - parameter completionHandler: A closure to execute when the task completes. It has a single argument for any error that might have occurred during the deletion.
    public func deleteTreatmentsById(_ ids:[String], completionHandler: @escaping (Error?) -> Void) {

        dataAccessQueue.async {
            let deleteGroup = DispatchGroup()
            var errors = [Error]()

            for id in ids {
                guard id != "NA" else {
                    continue
                }
                deleteGroup.enter()
                self.deleteFromNS(id, endpoint: .treatments) { (error) in
                    if let error = error {
                        errors.append(error)
                    }
                    deleteGroup.leave()
                }
            }

            _ = deleteGroup.wait(timeout: DispatchTime.distantFuture)
            completionHandler(errors.first)
        }
    }
    
    /// Attempts to delete treatments from nightscout by objectId. This method will not retry if the network task failed.
    ///
    /// - parameter id:                An array of nightscout objectId strings
    /// - parameter completionHandler: A closure to execute when the task completes. It has a single argument for any error that might have occurred during the deletion.
    public func deleteTreatmentsByObjectId(_ ids:[String], completionHandler: @escaping (Error?) -> Void) {
        let deleteGroup = DispatchGroup()
        var errors = [Error]()
        
        dataAccessQueue.async {
            
            for id in ids {
                guard id != "NA" else {
                    continue
                }
                deleteGroup.enter()
                self.deleteFromNS(id, endpoint: .treatments) { (error) in
                    if let error = error {
                        errors.append(error)
                    }
                    deleteGroup.leave()
                }
            }

            _ = deleteGroup.wait(timeout: DispatchTime.distantFuture)
            completionHandler(errors.first)
        }
    }


    public func uploadDeviceStatus(_ status: DeviceStatus) {
        deviceStatuses.append(status.dictionaryRepresentation)
        flushAll()
    }
    
    // MARK: - Fetching

    public func fetchCurrentProfile(completion: @escaping (Result<ProfileSet,Error>) -> Void) {
        let profileURL = url(for: .currentProfile)!
        getFromNS(url: profileURL) { (result) in
            switch result {
            case .failure(let error):
                print("Error fetching current profile: \(error)")
                completion(.failure(error))
            case .success(let rawResponse):
                guard let profileRaw = rawResponse as? ProfileSet.RawValue, let profileSet = ProfileSet(rawValue: profileRaw) else {
                    completion(.failure(UploadError.invalidResponse(reason: "Expected nightscout profile")))
                    return
                }

                completion(.success(profileSet))
            }
        }
    }

    public func fetchDeviceStatus(dateInterval: DateInterval, maxCount: Int = 50, completion: @escaping (Result<[DeviceStatus],Error>) -> Void) {
        var components = URLComponents(url: url(for: .deviceStatus)!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "find[created_at][$gte]", value: TimeFormat.timestampStrFromDate(dateInterval.start)),
            URLQueryItem(name: "find[created_at][$lte]", value: TimeFormat.timestampStrFromDate(dateInterval.end)),
            URLQueryItem(name: "count", value: String(maxCount))
        ]
        if let url = components.url {
            getFromNS(url: url) { (result) in
                switch result {
                case .failure(let error):
                    print("Error fetching treatments: \(error)")
                    completion(.failure(error))
                case .success(let rawResponse):
                    guard let returnedEntries = rawResponse as? [DeviceStatus.RawValue] else {
                        completion(.failure(UploadError.invalidResponse(reason: "Expected array of treatments")))
                        return
                    }

                    let entries = returnedEntries.compactMap({ (entry: DeviceStatus.RawValue) -> DeviceStatus? in
                        return DeviceStatus(rawValue: entry)
                    })

                    completion(.success(entries))
                }
            }
        } else {
            completion(.failure(UploadError.invalidParameters))
        }
    }


    public func fetchTreatments(dateInterval: DateInterval, maxCount: Int = 50, completion: @escaping (Result<[NightscoutTreatment],Error>) -> Void) {
        var components = URLComponents(url: url(for: .treatments)!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "find[timestamp][$gte]", value: TimeFormat.timestampStrFromDate(dateInterval.start)),
            URLQueryItem(name: "find[timestamp][$lte]", value: TimeFormat.timestampStrFromDate(dateInterval.end)),
            URLQueryItem(name: "count", value: String(maxCount))
        ]
        if let url = components.url {
            getFromNS(url: url) { (result) in
                switch result {
                case .failure(let error):
                    print("Error fetching treatments: \(error)")
                    completion(.failure(error))
                case .success(let rawResponse):
                    guard let returnedEntries = rawResponse as? [[String: Any]] else {
                        completion(.failure(UploadError.invalidResponse(reason: "Expected array of treatments")))
                        return
                    }

                    let entries = returnedEntries.compactMap({ (entry: [String: Any]) -> NightscoutTreatment? in
                        return NightscoutTreatment.fromServer(entry)
                    })

                    completion(.success(entries))
                }
            }
        } else {
            completion(.failure(UploadError.invalidParameters))
        }
    }

    public func fetchGlucose(dateInterval: DateInterval, maxCount: Int = 50, completion: @escaping (Result<[GlucoseEntry],Error>) -> Void) {
        var components = URLComponents(url: url(for: .entries)!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "find[dateString][$gte]", value: TimeFormat.timestampStrFromDate(dateInterval.start)),
            URLQueryItem(name: "find[dateString][$lte]", value: TimeFormat.timestampStrFromDate(dateInterval.end)),
            URLQueryItem(name: "count", value: String(maxCount))
        ]
        if let url = components.url {
            getFromNS(url: url) { (result) in
                switch result {
                case .failure(let error):
                    print("Error fetching glucose: \(error)")
                    completion(.failure(error))
                case .success(let rawResponse):
                    guard let returnedEntries = rawResponse as? [GlucoseEntry.RawValue] else {
                        completion(.failure(UploadError.invalidResponse(reason: "Expected array of glucose entries")))
                        return
                    }

                    let entries = returnedEntries.compactMap{ GlucoseEntry(rawValue: $0) }
                    completion(.success(entries))
                }
            }
        } else {
            completion(.failure(UploadError.invalidParameters))
        }
    }
    
    
    // MARK: - Loop Notifications

    public func startOverride(overrideName: String, reasonDisplay: String, durationTime: TimeInterval) async throws {

        let jsonDict: [String: String] = [
            "reason": overrideName,
            "reasonDisplay": reasonDisplay,
            "eventType": "Temporary Override",
            "duration": "\(durationTime.minutes)",
            "notes": ""
        ]
        
        try await postNotification(payload: jsonDict)
    }
    
    public func cancelOverride() async throws {

        let jsonDict: [String: String] = [
            "eventType": "Temporary Override Cancel",
            "duration": "0"
        ]
        
        try await postNotification(payload: jsonDict)
    }
    
    public func deliverBolus(amountInUnits: Double, otp: String) async throws  {

        let jsonDict: [String: String] = [
            "eventType": "Remote Bolus Entry",
            "remoteBolus": "\(amountInUnits)",
            "otp": otp
        ]
        
        try await postNotification(payload: jsonDict)
    }
    
    public func deliverCarbs(amountInGrams: Double, absorptionTime: TimeInterval, consumedDate: Date? = nil, otp: String) async throws  {

        var jsonDict: [String: String] = [
            "eventType": "Remote Carbs Entry",
            "remoteCarbs": "\(amountInGrams)",
            "remoteAbsorption": "\(absorptionTime.hours)",
            "otp": otp
        ]
        
        if let consumedDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions =  [.withInternetDateTime, .withFractionalSeconds]
            jsonDict["created_at"] = formatter.string(from: consumedDate)
        }
        
        try await postNotification(payload: jsonDict)
    }

    public func postNotification(payload: [String: String]) async throws  {
        guard let url = url(for: .notifications) else {
            throw UploadError.missingConfiguration
        }
        
        let _ = try await postToNS(payload, url: url)
    }
    
    // MARK: - Uploading

    public func uploadProfile(profileSet: ProfileSet, completion: @escaping (Result<[String],Error>) -> Void)  {
        guard let url = url(for: .profile) else {
            completion(.failure(UploadError.missingConfiguration))
            return
        }

        postToNS([profileSet.dictionaryRepresentation], url: url, completion: completion)
    }
    
    public func uploadProfiles(_ profileSets: [ProfileSet], completion: @escaping (Result<Bool, Error>) -> Void)  {
        postToNS(profileSets.map { $0.dictionaryRepresentation }, endpoint: .profile, completion: completion)
    }

    public func updateProfile(profileSet: ProfileSet, id: String, completion: @escaping (Error?) -> Void) {
        guard let url = url(for: .profile) else {
            completion(UploadError.missingConfiguration)
            return
        }
        
        var rep = profileSet.dictionaryRepresentation
        rep["_id"] = id
        putToNS(rep, url: url, completion: completion)
    }

    // MARK: - Uploading
    
    public func flushAll() {
        flushDeviceStatuses()
        flushEntries()
        flushTreatments()
    }

    fileprivate func deleteFromNS(_ id: String, endpoint: Endpoint, completion: @escaping (Error?) -> Void)  {
        let resource = "\(endpoint.rawValue)/\(id)"
        guard let url = url(with: resource) else {
            completion(UploadError.missingConfiguration)
            return
        }
        
        callNS(nil, url: url, method: "DELETE") { (result) in
            switch result {
            case .success( _):
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }

    func putToNS(_ json: Any, url:URL, completion: @escaping (Error?) -> Void) {
        callNS(json, url: url, method: "PUT") { (result) in
            switch result {
            case .success( _):
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }

    fileprivate func postToNS(_ json: [Any], endpoint: Endpoint, completion: @escaping (Result<Bool, Error>) -> Void)  {
        guard !json.isEmpty else {
            completion(.success(false))
            return
        }

        guard let url = url(for: endpoint) else {
            completion(.failure(UploadError.missingConfiguration))
            return
        }

        postToNS(json, url: url) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                completion(.success(true))
            }
        }
    }

    func postToNS(_ json: [Any], url:URL, completion: @escaping (Result<[String],Error>) -> Void) {
        if json.count == 0 {
            completion(.success([]))
            return
        }

        callNS(json, url: url, method: "POST") { (result) in
            switch result {
            case .success(let postResponse):
                guard let insertedEntries = postResponse as? [[String: Any]], insertedEntries.count == json.count else {
                    completion(.failure(UploadError.invalidResponse(reason: "Expected array of \(json.count) objects in JSON response: \(postResponse)")))
                    return
                }

                let ids = insertedEntries.map({ (entry: [String: Any]) -> String in
                    if let id = entry["_id"] as? String {
                        return id
                    } else {
                        // Upload still succeeded; likely that this is an old version of NS
                        // Instead of failing (which would cause retries later, we just mark
                        // This entry has having an id of 'NA', which will let us consider it
                        // uploaded.
                        //throw UploadError.invalidResponse(reason: "Invalid/missing id in response.")
                        return "NA"
                    }
                })
                completion(.success(ids))
            case .failure(let error):
                completion(.failure(error))
            }

        }
    }

    func getFromNS(url: URL, completion: @escaping (Result<Any,Error>) -> Void) {
        callNS(nil, url: url, method: "GET") { (result) in
            completion(result)
        }
    }

    func callNS(_ json: Any?, url:URL, method:String, completion: @escaping (Result<Any,Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiSecret.sha1, forHTTPHeaderField: "api-secret")
        
        do {
            if let json = json {
                let sendData = try JSONSerialization.data(withJSONObject: json, options: [])
                let task = URLSession.shared.uploadTask(with: request, from: sendData, completionHandler: { (data, response, error) in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(.failure(UploadError.invalidResponse(reason: "Response is not HTTPURLResponse")))
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        let error = UploadError.httpError(status: httpResponse.statusCode, body:String(data: data!, encoding: String.Encoding.utf8)!)
                        completion(.failure(error))
                        return
                    }
                    
                    guard let data = data, !data.isEmpty else {
                        completion(.success([]))
                        return
                    }

                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
                        completion(.success(json))
                    } catch {
                        completion(.failure(error))
                        return
                    }
                })
                task.resume()
            } else {
                let task = URLSession.shared.dataTask(with: request, completionHandler: { (data, response, error) in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(.failure(UploadError.invalidResponse(reason: "Response is not HTTPURLResponse")))
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        let error = UploadError.httpError(status: httpResponse.statusCode, body:String(data: data!, encoding: String.Encoding.utf8)!)
                        completion(.failure(error))
                        return
                    }

                    guard let data = data else {
                        completion(.failure(UploadError.invalidResponse(reason: "No data in response")))
                        return
                    }

                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
                        completion(.success(json))
                    } catch {
                        completion(.failure(error))
                        return
                    }
                })
                task.resume()
            }

        } catch let error {
            completion(.failure(error))
        }
    }
    
    func postToNS<T: Decodable>(_ json: Any, url: URL, jsonReturnType: T.Type?) async throws -> T {
        let data = try await postToNS(json, url: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func postToNS(_ json: Any, url:URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiSecret.sha1, forHTTPHeaderField: "api-secret")
        
        let sendData = try JSONSerialization.data(withJSONObject: json, options: [])
        let (data, urlResponse) = try await URLSession.shared.upload(for: request, from: sendData)

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw UploadError.invalidResponse(reason: "Response is not HTTPURLResponse")
        }

        if httpResponse.statusCode != 200 {
            throw UploadError.httpError(status: httpResponse.statusCode, body:String(data: data, encoding: String.Encoding.utf8)!)
        }
        
        return data
    }
    
    func flushDeviceStatuses() {
        guard let url = url(for: .deviceStatus) else {
            return
        }

        let inFlight = deviceStatuses
        deviceStatuses = []
        postToNS(inFlight as [Any], url: url) { (result) in
            switch result {
            case .failure(let error):
                self.errorHandler?(error, "Uploading device status")
                // Requeue
                self.deviceStatuses.append(contentsOf: inFlight)
            case .success(_):
                break
            }
        }
    }
    
    public func uploadDeviceStatuses(_ deviceStatuses: [DeviceStatus], completion: @escaping (Result<Bool, Error>) -> Void) {
        postToNS(deviceStatuses.map { $0.dictionaryRepresentation }, endpoint: .deviceStatus, completion: completion)
    }

    public func flushEntries() {
        guard let url = url(for: .entries) else {
            return
        }

        let inFlight = entries
        entries = []
        postToNS(inFlight.map({$0.dictionaryRepresentation}), url: url) { (result) in
            switch result {
            case .failure(let error):
                self.errorHandler?(error, "Uploading nightscout entries")
                // Requeue
                self.entries.append(contentsOf: inFlight)
            case .success(_):
                break
            }
        }
    }
    
    public func uploadEntries(_ entries: [GlucoseEntry], completion: @escaping (Result<Bool, Error>) -> Void) {
        print("Uploading \(entries)")
        postToNS(entries.map { $0.dictionaryRepresentation }, endpoint: .entries, completion: completion)
    }

    func flushTreatments() {
        guard let url = url(for: .treatments) else {
            return
        }

        let inFlight = treatmentsQueue
        treatmentsQueue = []
        postToNS(inFlight.map({$0.dictionaryRepresentation}), url: url) { (result) in
            switch result {
            case .failure(let error):
                self.errorHandler?(error, "Uploading nightscout treatment records")
                // Requeue
                self.treatmentsQueue.append(contentsOf: inFlight)
            case .success:
                break
            }
        }
    }
    
    public func checkAuth(_ completion: @escaping (Error?) -> Void) {
        guard let testURL = url(for: .authTest) else {
            completion(UploadError.missingConfiguration)
            return
        }
        
        var request = URLRequest(url: testURL)
        
        request.setValue("application/json", forHTTPHeaderField:"Content-Type")
        request.setValue("application/json", forHTTPHeaderField:"Accept")
        request.setValue(apiSecret.sha1, forHTTPHeaderField:"api-secret")
        let task = URLSession.shared.dataTask(with: request, completionHandler: { (data, response, error) in
            if let error = error {
                completion(error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse ,
                httpResponse.statusCode != 200 {
                    if httpResponse.statusCode == 401 {
                        completion(UploadError.unauthorized)
                    } else {
                        let error = UploadError.httpError(status: httpResponse.statusCode, body:String(data: data!, encoding: String.Encoding.utf8)!)
                        completion(error)
                    }
            } else {
                completion(nil)
            }
        })
        task.resume()
    }
}

