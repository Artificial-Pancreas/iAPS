import CommonCrypto
import Foundation
import NightscoutKit

actor NightscoutAPI {
    private let url: URL
    private let secret: String?

    private let service = NetworkService()

    private let nightscoutClient: NightscoutClient

    init(url: URL, secret: String? = nil) {
        self.url = url
        self.secret = secret?.nonEmpty
        nightscoutClient = NightscoutClient(siteURL: url, apiSecret: secret)
    }

    private enum Config {
        static let uploadEntriesPath = "/api/v1/entries.json"
        static let treatmentsPath = "/api/v1/treatments.json"
        static let statusPath = "/api/v1/devicestatus.json"
        static let profilePath = "/api/v1/profile.json"
        static let retryCount = 2
        static let timeout: TimeInterval = 60
    }
}

extension GlucoseEntry: @retroactive @unchecked Sendable {}

extension NightscoutAPI {
    func checkConnection() async throws {
        struct Check: Codable, Equatable {
            var eventType = "Note"
            var enteredBy = "iAPS"
            var notes = "iAPS connected"
        }

        return try await sendPostRequest(Config.treatmentsPath, payload: Check())
    }

    func fetchGlucose(dateInterval: DateInterval) async -> [GlucoseEntry] {
        await withCheckedContinuation { continuation in
            nightscoutClient.fetchGlucose(dateInterval: dateInterval, maxCount: 500) { result in
                switch result {
                case let .success(entries):
                    continuation.resume(returning: entries)
                case let .failure(error):
                    warning(.nightscout, "Glucose fetching error: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchCarbs(sinceDate: Date? = nil) async -> [CarbsEntry] {
        var queryItems = [
            URLQueryItem(name: "find[carbs][$exists]", value: "true"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: CarbsEntry.manual.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: CarbsEntry.watch.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: CarbsEntry.shortcut.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.trio.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            )
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            queryItems.append(dateItem)
        }

        do {
            return try await sendGetRequest(
                Config.treatmentsPath,
                query: queryItems,
                as: [CarbsEntry].self,
                allowsConstrainedNetworkAccess: false
            )
        } catch {
            warning(.nightscout, "Carbs fetching error: \(error.localizedDescription)")
            return []
        }
    }

    func deleteCarbs(_ date: Date) async throws {
        let queryItems = [
            URLQueryItem(name: "find[carbs][$exists]", value: "true"),
            URLQueryItem(
                name: "find[creation_date][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]

        try await sendDeleteRequest(Config.treatmentsPath, query: queryItems, allowsConstrainedNetworkAccess: false)
    }

    func deleteManualGlucose(at date: Date) async throws {
        let queryItems = [
            URLQueryItem(name: "find[glucose][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]

        try await sendDeleteRequest(Config.treatmentsPath, query: queryItems, allowsConstrainedNetworkAccess: false)
    }

    func deleteInsulin(at date: Date) async throws {
        let queryItems = [
            URLQueryItem(name: "find[bolus][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]

        try await sendDeleteRequest(Config.treatmentsPath, query: queryItems, allowsConstrainedNetworkAccess: false)
    }

    func fetchTempTargets(sinceDate: Date? = nil) async -> [TempTarget] {
        var queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Temporary+Target"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: TempTarget.manual.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(name: "find[duration][$exists]", value: "true")
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            queryItems.append(dateItem)
        }

        do {
            return try await sendGetRequest(
                Config.treatmentsPath,
                query: queryItems,
                as: [TempTarget].self,
                allowsConstrainedNetworkAccess: false
            )
        } catch {
            warning(.nightscout, "TempTarget fetching error: \(error.localizedDescription)")
            return []
        }
    }

    func fetchAnnouncement(sinceDate: Date? = nil) async -> [Announcement] {
        var queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Announcement"),
            URLQueryItem(
                name: "find[enteredBy]",
                value: Announcement.remote.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            )
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            queryItems.append(dateItem)
        }

        do {
            return try await sendGetRequest(
                Config.treatmentsPath,
                query: queryItems,
                as: [Announcement].self,
                allowsConstrainedNetworkAccess: false
            )
        } catch {
            warning(.nightscout, "Announcement fetching error: \(error.localizedDescription)")
            return []
        }
    }

    func deleteAnnouncements() async throws {
        let queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Announcement"),
            URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds
                    .string(from: Date.now)
            )
        ]

        try await sendDeleteRequest(Config.treatmentsPath, query: queryItems, allowsConstrainedNetworkAccess: false)
    }

    func deleteNSoverride() async throws {
        let queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Exercise"),
            URLQueryItem(name: "count", value: "\(1)"), // Delete latest
            URLQueryItem(name: "find[enteredBy]", value: "iAPS") // Don't delete entries created in NS
        ]

        try await sendDeleteRequest(Config.treatmentsPath, query: queryItems, allowsConstrainedNetworkAccess: false)
    }

    func deleteOverride(at date: Date) async throws {
        let queryItems = [
            URLQueryItem(name: "find[Exercise][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]
        try await sendDeleteRequest(Config.treatmentsPath, query: queryItems, allowsConstrainedNetworkAccess: false)
    }

    // Dev work. Delete all exercise events
    func deleteAllNSoverrrides() async throws {
        let queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Exercise")
        ]
        try await sendDeleteRequest(Config.treatmentsPath, query: queryItems, allowsConstrainedNetworkAccess: false)
    }

    func uploadTreatments(_ treatments: [NigtscoutTreatment]) async throws {
        try await sendPostRequest(Config.treatmentsPath, payload: treatments)
    }

    func uploadEcercises(_ override: [NigtscoutExercise]) async throws {
        try await sendPostRequest(Config.treatmentsPath, payload: override)
    }

    func uploadGlucose(_ glucose: [GlucoseEntry]) async throws -> Bool {
        debug(.nightscout, "NS Client: uploading \(glucose.count) glucose entries")
        return try await withCheckedThrowingContinuation { continuation in
            nightscoutClient.uploadEntries(glucose) { result in
                switch result {
                case let .success(res):
                    continuation.resume(returning: res)
                case let .failure(error):
                    warning(.nightscout, "Glucose fetching error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func uploadStatus(_ status: NightscoutStatus) async throws {
        try await sendPostRequest(Config.statusPath, payload: status)
    }

    func uploadProfile(_ profile: NightscoutProfileStore) async throws {
        try await sendPostRequest(Config.profilePath, payload: profile)
    }

    func uploadPreferences(_ preferences: Preferences) async throws {
        try await sendPostRequest(Config.profilePath, payload: preferences)
    }

    func fetchProfile() async throws -> [FetchedNightscoutProfileStore] {
        try await sendGetRequest(
            Config.profilePath,
            query: [URLQueryItem(name: "count", value: "1")],
            as: [FetchedNightscoutProfileStore].self,
            allowsConstrainedNetworkAccess: false
        )
    }
}

extension NightscoutAPI {
    private func makeRequest(
        _ path: String,
        query: [URLQueryItem]? = nil,
        allowsConstrainedNetworkAccess: Bool = false
    ) -> URLRequest {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = path
        components.queryItems = query

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return request
    }

    private func makeRequest<Req>(
        _ path: String,
        query: [URLQueryItem]? = nil,
        payload req: Req,
        allowsConstrainedNetworkAccess: Bool = false
    ) -> URLRequest where Req: Encodable {
        var request = makeRequest(path, query: query, allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONCoding.encoder.encode(req)

        return request
    }

    private func sendGetRequest<Resp: Decodable>(
        _ path: String,
        query: [URLQueryItem]? = nil,
        as type: Resp.Type,
        allowsConstrainedNetworkAccess: Bool = false
    ) async throws -> Resp {
        let request = makeRequest(path, query: query, allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess)
        let data = try await service.runAsync(request, retries: Config.retryCount)
        return try JSONCoding.decoder.decode(type, from: data)
    }

    private func sendDeleteRequest(
        _ path: String,
        query: [URLQueryItem]? = nil,
        allowsConstrainedNetworkAccess: Bool = false
    ) async throws {
        var request = makeRequest(path, query: query, allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess)
        request.httpMethod = "DELETE"
        _ = try await service.runAsync(request, retries: Config.retryCount)
    }

    private func sendPostRequest<Req: Encodable, Resp: Decodable>(
        _ path: String,
        query: [URLQueryItem]? = nil,
        payload req: Req,
        as type: Resp.Type,
        allowsConstrainedNetworkAccess: Bool = false
    ) async throws -> Resp {
        let request = makeRequest(
            path,
            query: query,
            payload: req,
            allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess
        )
        let data = try await service.runAsync(request, retries: Config.retryCount)
        return try JSONCoding.decoder.decode(type, from: data)
    }

    private func sendPostRequest<Req: Encodable>(
        _ path: String,
        query: [URLQueryItem]? = nil,
        payload req: Req,
    ) async throws {
        let request = makeRequest(path, query: query, payload: req)
        _ = try await service.runAsync(request, retries: Config.retryCount)
    }
}

private extension String {
    func sha1() -> String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}
