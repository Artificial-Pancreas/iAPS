import Combine
import Foundation
import Swinject
import UIKit

protocol LibreLinkManager {
    func createConnection(url: URL, username: String, password: String) -> AnyPublisher<LibreLinkToken, Error>
    func uploadIfNeeded()
    func uploadGlucose(url: URL, token: String, from: TimeInterval, to: TimeInterval)
        -> AnyPublisher<MeasurementsUploadResult, Error>
}

enum LibreLinkManagerError: LocalizedError {
    case wrongToken
    case wrongSettings
    case wrongPasswordOrLogin
    case wrongLastUploadDate
    case notGlucoseToUpload
    case notAllowUploadData
    case tooEarlyToUpload
    case error(String)

    var errorDescription: String? {
        switch self {
        case .wrongToken:
            return "Wrong connection's token"
        case .wrongSettings:
            return "Wrong connection's settings"
        case .wrongPasswordOrLogin:
            return "Wrong password or login"
        case .wrongLastUploadDate:
            return "Last upload date to LibreLink is more, that current date. Try later or check preferences"
        case .notGlucoseToUpload:
            return "Have not new glucose to upload"
        case .notAllowUploadData:
            return "Not allow upload data to LibreView"
        case .tooEarlyToUpload:
            return "Too early to upload data"
        case let .error(description):
            return description
        }
    }
}

class BaseLibreLinkManager: Injectable {
    @Injected() private var reachabilityManager: ReachabilityManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var keychain: Keychain!

    private let processQueue = DispatchQueue(label: "BaseLibreLinkManager.processQueue")
    private let service = NetworkService()

    private var lifetime = Lifetime()

    enum Config {
        static let authenticationPath = "/lsl/api/nisperson/getauthentication"
        static let measurementPath = "lsl/api/measurements"
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private func subscribe() {
        _ = reachabilityManager.startListening(onQueue: processQueue) { status in
            debug(.librelink, "Network status: \(status)")
        }
    }
}

extension BaseLibreLinkManager: LibreLinkManager {
    func uploadIfNeeded() {
        debug(.librelink, "Start uploading data to LibreLink")
        do {
            guard settingsManager.settings.libreViewLastAllowUploadGlucose else {
                throw LibreLinkManagerError.notAllowUploadData
            }
            guard let server = LibreViewConfig.Server.byViewTag(settingsManager.settings.libreViewServer),
                  let url = server == .custom ? URL(string: settingsManager.settings.libreViewCustomServer) :
                  URL(string: "https://\(server.rawValue)")
            else {
                throw LibreLinkManagerError.wrongSettings
            }
            guard let token = keychain.getValue(String.self, forKey: LibreViewConfig.Config.lvTokenKey), token != "" else {
                throw LibreLinkManagerError.wrongToken
            }
            let currentTimestamp = Date().timeIntervalSince1970
            let nextUploadTimeStamp = settingsManager.settings.libreViewLastUploadTimestamp + settingsManager.settings
                .libreViewNextUploadDelta
            guard currentTimestamp >= nextUploadTimeStamp else {
                throw LibreLinkManagerError.tooEarlyToUpload
            }

            uploadGlucose(
                url: url,
                token: token,
                from: settingsManager.settings.libreViewLastUploadTimestamp,
                to: currentTimestamp
            )
            .replaceError(with: false)
            .sink { [weak self] uploadResult in
                guard uploadResult else { return }
                self?.settingsManager.settings.libreViewLastUploadTimestamp = currentTimestamp
            }
            .store(in: &lifetime)
            debug(.librelink, "Upload to libreLink successfully ended")
        } catch {
            debug(.librelink, "Error during uploading data to LibreLink: \(error.localizedDescription)")
        }
    }

    func uploadGlucose(
        url: URL,
        token: String,
        from lastUploadTimestamp: TimeInterval,
        to currentTimestamp: TimeInterval
    ) -> AnyPublisher<MeasurementsUploadResult, Error> {
        debug(.librelink, "Start uploading glucose to LibreLink from \(lastUploadTimestamp) to \(currentTimestamp)")
        guard token != "" else {
            return Fail(error: LibreLinkManagerError.wrongToken).eraseToAnyPublisher()
        }

        guard lastUploadTimestamp < currentTimestamp else {
            return Fail(error: LibreLinkManagerError.wrongLastUploadDate).eraseToAnyPublisher()
        }
        let notUploadedGlucose = glucoseStorage.recent().filter { glucose in
            glucose.dateString.timeIntervalSince1970 > lastUploadTimestamp
        }

        guard notUploadedGlucose.isNotEmpty else {
            return Fail(error: LibreLinkManagerError.notGlucoseToUpload).eraseToAnyPublisher()
        }

        var request = URLRequest(url: url.appendingPathComponent(Config.measurementPath))
        let requestBody = MeasurementRequest(
            token: token,
            bg: notUploadedGlucose.compactMap { bgItem -> PreparedBloodGlucose? in

                guard let glucose = bgItem.glucose else { return nil }

                return PreparedBloodGlucose(
                    id: Int(bgItem.dateString.timeIntervalSince1970),
                    value: glucose,
                    date: bgItem.dateString,
                    trend: bgItem.direction ?? .none
                )
            }
        )
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try! JSONCoding.encoder.encode(requestBody)

        return service.run(request)
            .decode(type: MeasurementResponse.self, decoder: JSONDecoder())
            .tryMap { response -> MeasurementsUploadResult in
                guard response.status == 0 else {
                    if response.status == 24 { throw LibreLinkManagerError.wrongPasswordOrLogin }
                    else { throw LibreLinkManagerError.error(response.reason ?? "Something was wrong") }
                }
                self.updateUploadTimestampDelta()
                debug(.librelink, "Finish uploading data to LibreLink. Was upload \(notUploadedGlucose.count) bloodGlucose items")
                return true
            }
            .eraseToAnyPublisher()
    }

    func createConnection(url: URL, username: String, password: String) -> AnyPublisher<LibreLinkToken, Error> {
        var request = URLRequest(url: url.appendingPathComponent(Config.authenticationPath))
        let requestBody = NetworkConnectionRequest(username: username, password: password)

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try! JSONCoding.encoder.encode(requestBody)

        return service.run(request)
            .decode(type: NetworkConnectionResponse.self, decoder: JSONDecoder())
            .tryMap { response in
                guard response.status == 0, let responseBody = response.result else {
                    if response.status == 10 { throw LibreLinkManagerError.wrongToken }
                    else { throw LibreLinkManagerError.error(response.reason ?? "Something was wrong") }
                }
                return responseBody.userToken
            }
            .eraseToAnyPublisher()
    }

    private func updateUploadTimestampDelta() {
        guard let frequency = LibreViewConfig.UploadsFrequency(rawValue: settingsManager.settings.libreViewFrequenceUploads)
        else {
            settingsManager.settings.libreViewFrequenceUploads = 0
            settingsManager.settings.libreViewNextUploadDelta = 0
            return
        }
        settingsManager.settings.libreViewNextUploadDelta = frequency.secondsToNextUpload
    }
}

// MARK: - Subtypes

typealias LibreLinkToken = String
typealias MeasurementsUploadResult = Bool

extension BaseLibreLinkManager {
    // MARK: Local models

    struct PreparedBloodGlucose {
        var id: Int
        var value: Int
        var date: Date
        var trend: BloodGlucose.Direction
    }

    // MARK: Connection

    struct NetworkConnectionRequest: Codable {
        var username: String
        var password: String
        var domain = "Libreview"
        var gatewayType = "FSLibreLink.iOS"
        var deviceID = UIDevice.current.identifierForVendor!.uuidString
        var setDevice = true
    }

    struct NetworkConnectionResponse: Codable {
        let status: Int
        let reason: String?
        let result: Result?

        struct Result: Codable {
            let userToken, accountID, userName, firstName: String
            let lastName, middleInitial, email, country: String
            let culture: String
            let timezone: String?
            let dateOfBirth: String
            let backupFileExists, isHCP, validated, needToAcceptPolicies: Bool
            let communicationLanguage, uiLanguage: String
            let supportedDevices: String?
            let created, guardianLastName, guardianFirstName, domainData: String

            enum CodingKeys: String, CodingKey {
                case userToken = "UserToken"
                case accountID = "AccountId"
                case userName = "UserName"
                case firstName = "FirstName"
                case lastName = "LastName"
                case middleInitial = "MiddleInitial"
                case email = "Email"
                case country = "Country"
                case culture = "Culture"
                case timezone = "Timezone"
                case dateOfBirth = "DateOfBirth"
                case backupFileExists = "BackupFileExists"
                case isHCP = "IsHCP"
                case validated = "Validated"
                case needToAcceptPolicies = "NeedToAcceptPolicies"
                case communicationLanguage = "CommunicationLanguage"
                case uiLanguage = "UiLanguage"
                case supportedDevices = "SupportedDevices"
                case created = "Created"
                case guardianLastName = "GuardianLastName"
                case guardianFirstName = "GuardianFirstName"
                case domainData = "DomainData"
            }
        }
    }

    // MARK: Measurement

    struct MeasurementRequest: Encodable {
        let gatewayType = "FSLibreLink.iOS"
        let domain = "Libreview"
        let userToken: String
        let deviceData: DeviceData

        init(token: String, bg: [PreparedBloodGlucose]) {
            userToken = token
            deviceData = DeviceData(bg: bg)
        }

        struct DeviceData: Encodable {
            let header = Header()
            let measurementLog: MeasurementLog

            init(bg: [PreparedBloodGlucose]) {
                measurementLog = MeasurementLog(bg: bg)
            }
        }

        struct Header: Encodable {
            let device = Device()
        }

        struct Device: Encodable {
            let hardwareDescriptor = "iPhone14,3"
            let osVersion = "16.0"
            let modelName = "com.abbott.librelink.ru"
            let osType = "iOS"
            let uniqueIdentifier = UIDevice.current.identifierForVendor!.uuidString
            let hardwareName = "iPhone"
        }

        struct MeasurementLog: Encodable {
            let bloodGlucoseEntries = [String]()
            let capabilities = [
                "scheduledContinuousGlucose",
                "unscheduledContinuousGlucose",
                "bloodGlucose",
                "insulin",
                "food",
                "generic-com.abbottdiabetescare.informatics.exercise",
                "generic-com.abbottdiabetescare.informatics.customnote",
                "generic-com.abbottdiabetescare.informatics.ondemandalarm.low",
                "generic-com.abbottdiabetescare.informatics.ondemandalarm.high",
                "generic-com.abbottdiabetescare.informatics.ondemandalarm.projectedlow",
                "generic-com.abbottdiabetescare.informatics.ondemandalarm.projectedhigh",
                "generic-com.abbottdiabetescare.informatics.sensorstart",
                "generic-com.abbottdiabetescare.informatics.error",
                "generic-com.abbottdiabetescare.informatics.isfGlucoseAlarm",
                "generic-com.abbottdiabetescare.informatics.alarmSetting"
            ]
            let scheduledContinuousGlucoseEntries: [ScheduledContinuousGlucoseEntry]
            let insulinEntries = [String]()
            let foodEntries = [String]()
            let unscheduledContinuousGlucoseEntries: [UnscheduledContinuousGlucoseEntry]

            init(bg: [PreparedBloodGlucose]) {
                scheduledContinuousGlucoseEntries = bg.map { bgItem in ScheduledContinuousGlucoseEntry(bg: bgItem) }
                if let lastBG = bg.last {
                    unscheduledContinuousGlucoseEntries = [UnscheduledContinuousGlucoseEntry(bg: lastBG)]
                } else {
                    unscheduledContinuousGlucoseEntries = []
                }
            }
        }

        struct ScheduledContinuousGlucoseEntry: Encodable {
            let extendedProperties: ExtendedScheduledProperties
            let recordNumber: Int
            let timestamp: String
            let valueInMgPerDL: Int

            init(bg: PreparedBloodGlucose) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
                formatter.timeZone = TimeZone.current

                recordNumber = bg.id
                timestamp = formatter.string(from: bg.date)
                valueInMgPerDL = Int(bg.value)

                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                extendedProperties = ExtendedScheduledProperties(
                    bgValue: bg.value,
                    factoryTimestamp: formatter.string(from: bg.date)
                )
            }
        }

        struct ExtendedScheduledProperties: Encodable {
            let highOutOfRange: String
            let canMerge = "true"
            let isFirstAfterTimeChange = false
            let factoryTimestamp: String
            let lowOutOfRange: String

            init(bgValue: Int, factoryTimestamp: String) {
                if bgValue <= 70 {
                    highOutOfRange = "false"
                    lowOutOfRange = "true"
                } else if bgValue >= 180 {
                    highOutOfRange = "true"
                    lowOutOfRange = "false"
                } else {
                    highOutOfRange = "false"
                    lowOutOfRange = "false"
                }
                self.factoryTimestamp = factoryTimestamp
            }
        }

        struct UnscheduledContinuousGlucoseEntry: Encodable {
            let extendedProperties: ExtendedUnscheduledProperties
            let recordNumber: Int
            let timestamp: String
            let valueInMgPerDL: Int

            init(bg: PreparedBloodGlucose) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
                formatter.timeZone = TimeZone.current

                recordNumber = bg.id
                timestamp = formatter.string(from: bg.date)
                valueInMgPerDL = Int(bg.value)

                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                extendedProperties = ExtendedUnscheduledProperties(
                    bgValue: bg.value,
                    factoryTimestamp: formatter.string(from: bg.date),
                    direction: bg.trend
                )
            }
        }

        struct ExtendedUnscheduledProperties: Encodable {
            let highOutOfRange: String
            let isActionable = true
            let trendArrow: String
            let isFirstAfterTimeChange = false
            let factoryTimestamp: String
            let lowOutOfRange: String

            init(bgValue: Int, factoryTimestamp: String, direction: BloodGlucose.Direction) {
                if bgValue <= 70 {
                    highOutOfRange = "false"
                    lowOutOfRange = "true"
                } else if bgValue >= 180 {
                    highOutOfRange = "true"
                    lowOutOfRange = "false"
                } else {
                    highOutOfRange = "false"
                    lowOutOfRange = "false"
                }
                self.factoryTimestamp = factoryTimestamp
                switch direction {
                case .doubleUp,
                     .singleUp,
                     .tripleUp:
                    trendArrow = "Rising"
                case .flat,
                     .fortyFiveDown,
                     .fortyFiveUp:
                    trendArrow = "Stable"
                case .doubleDown,
                     .singleDown,
                     .tripleDown:
                    trendArrow = "Falling"
                case .none,
                     .notComputable,
                     .rateOutOfRange:
                    trendArrow = "Stable"
                }
            }
        }
    }

    struct MeasurementResponse: Decodable {
        let status: Int
        let result: Result?
        let reason: String?

        struct Result: Decodable {
            let uploadID: String?
            let status: Int?
            let measurementCounts: MeasurementCounts?
            let itemCount: Int?
            let createdDateTime, serialNumber: String?
        }

        struct MeasurementCounts: Decodable {
            let scheduledGlucoseCount, unScheduledGlucoseCount, bloodGlucoseCount, insulinCount: Int?
            let genericCount, foodCount, ketoneCount, totalCount: Int?
        }
    }
}
