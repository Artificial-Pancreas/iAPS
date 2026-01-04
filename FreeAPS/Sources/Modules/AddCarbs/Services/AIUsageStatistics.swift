import Foundation

enum AIUsageStatistics {
    enum RequestType: String, Codable {
        case image
        case text

        var displayName: String {
            switch self {
            case .image: return "Image"
            case .text: return "Text"
            }
        }
    }

    /// Statistics for a specific AI model and request type
    struct Statistics: Codable, Equatable {
        let modelKey: String // The AIModel's rawValue (e.g., "openAI/gpt-4o")
        let requestType: RequestType // image or text
        var requestCount: Int
        var successCount: Int
        var failureCount: Int
        var totalProcessingTime: TimeInterval
        var totalSuccessProcessingTime: TimeInterval
        var totalFailureProcessingTime: TimeInterval

        // Complexity-based tracking (food item counts for successful requests)
        var zeroFoodCount: Int
        var zeroFoodTotalProcessingTime: TimeInterval
        var oneFoodCount: Int
        var oneFoodTotalProcessingTime: TimeInterval
        var twoFoodCount: Int
        var twoFoodTotalProcessingTime: TimeInterval
        var multipleFoodCount: Int
        var multipleFoodTotalProcessingTime: TimeInterval

        /// Average processing time per request (all requests)
        var averageProcessingTime: TimeInterval {
            guard requestCount > 0 else { return 0 }
            return totalProcessingTime / Double(requestCount)
        }

        /// Average processing time per successful request
        var averageSuccessProcessingTime: TimeInterval {
            guard successCount > 0 else { return 0 }
            return totalSuccessProcessingTime / Double(successCount)
        }

        /// Average processing time per failed request
        var averageFailureProcessingTime: TimeInterval {
            guard failureCount > 0 else { return 0 }
            return totalFailureProcessingTime / Double(failureCount)
        }

        /// Success rate as a percentage (0-100)
        var successRate: Double {
            guard requestCount > 0 else { return 0 }
            return (Double(successCount) / Double(requestCount)) * 100
        }

        /// Failure rate as a percentage (0-100)
        var failureRate: Double {
            guard requestCount > 0 else { return 0 }
            return (Double(failureCount) / Double(requestCount)) * 100
        }

        // MARK: - Complexity-specific computed properties

        /// Average processing time for requests that found zero food items
        var averageZeroFoodProcessingTime: TimeInterval {
            guard zeroFoodCount > 0 else { return 0 }
            return zeroFoodTotalProcessingTime / Double(zeroFoodCount)
        }

        /// Average processing time for requests that found one food item
        var averageOneFoodProcessingTime: TimeInterval {
            guard oneFoodCount > 0 else { return 0 }
            return oneFoodTotalProcessingTime / Double(oneFoodCount)
        }

        /// Average processing time for requests that found two food items
        var averageTwoFoodProcessingTime: TimeInterval {
            guard twoFoodCount > 0 else { return 0 }
            return twoFoodTotalProcessingTime / Double(twoFoodCount)
        }

        /// Average processing time for requests that found multiple (3+) food items
        var averageMultipleFoodProcessingTime: TimeInterval {
            guard multipleFoodCount > 0 else { return 0 }
            return multipleFoodTotalProcessingTime / Double(multipleFoodCount)
        }

        init(
            modelKey: String,
            requestType: RequestType,
            requestCount: Int = 0,
            successCount: Int = 0,
            failureCount: Int = 0,
            totalProcessingTime: TimeInterval = 0,
            totalSuccessProcessingTime: TimeInterval = 0,
            totalFailureProcessingTime: TimeInterval = 0,
            zeroFoodCount: Int = 0,
            zeroFoodTotalProcessingTime: TimeInterval = 0,
            oneFoodCount: Int = 0,
            oneFoodTotalProcessingTime: TimeInterval = 0,
            twoFoodCount: Int = 0,
            twoFoodTotalProcessingTime: TimeInterval = 0,
            multipleFoodCount: Int = 0,
            multipleFoodTotalProcessingTime: TimeInterval = 0
        ) {
            self.modelKey = modelKey
            self.requestType = requestType
            self.requestCount = requestCount
            self.successCount = successCount
            self.failureCount = failureCount
            self.totalProcessingTime = totalProcessingTime
            self.totalSuccessProcessingTime = totalSuccessProcessingTime
            self.totalFailureProcessingTime = totalFailureProcessingTime
            self.zeroFoodCount = zeroFoodCount
            self.zeroFoodTotalProcessingTime = zeroFoodTotalProcessingTime
            self.oneFoodCount = oneFoodCount
            self.oneFoodTotalProcessingTime = oneFoodTotalProcessingTime
            self.twoFoodCount = twoFoodCount
            self.twoFoodTotalProcessingTime = twoFoodTotalProcessingTime
            self.multipleFoodCount = multipleFoodCount
            self.multipleFoodTotalProcessingTime = multipleFoodTotalProcessingTime
        }
    }

    // MARK: - Public API

    /// Record a new AI request data point
    /// - Parameters:
    ///   - model: The AI model used
    ///   - requestType: Whether this is an image or text request
    ///   - processingTime: The time it took to process the request in seconds
    ///   - success: Whether the request was successful
    ///   - foodItemCount: The number of food items found (optional, only for successful requests)
    static func recordRequest(
        model: AIModel,
        requestType: RequestType,
        processingTime: TimeInterval,
        success: Bool,
        foodItemCount: Int? = nil
    ) {
        var statistics = loadStatistics()
        let key = "\(model.rawValue):\(requestType.rawValue)"

        if var existing = statistics[key] {
            existing.requestCount += 1
            existing.totalProcessingTime += processingTime
            if success {
                existing.successCount += 1
                existing.totalSuccessProcessingTime += processingTime

                // Update complexity-specific tracking for successful requests
                if let count = foodItemCount {
                    switch count {
                    case 0:
                        existing.zeroFoodCount += 1
                        existing.zeroFoodTotalProcessingTime += processingTime
                    case 1:
                        existing.oneFoodCount += 1
                        existing.oneFoodTotalProcessingTime += processingTime
                    case 2:
                        existing.twoFoodCount += 1
                        existing.twoFoodTotalProcessingTime += processingTime
                    default: // 3 or more
                        existing.multipleFoodCount += 1
                        existing.multipleFoodTotalProcessingTime += processingTime
                    }
                }
            } else {
                existing.failureCount += 1
                existing.totalFailureProcessingTime += processingTime
            }
            statistics[key] = existing
        } else {
            var newStats = Statistics(
                modelKey: model.rawValue,
                requestType: requestType,
                requestCount: 1,
                successCount: success ? 1 : 0,
                failureCount: success ? 0 : 1,
                totalProcessingTime: processingTime,
                totalSuccessProcessingTime: success ? processingTime : 0,
                totalFailureProcessingTime: success ? 0 : processingTime
            )

            // Update complexity-specific tracking for successful requests
            if success, let count = foodItemCount {
                switch count {
                case 0:
                    newStats.zeroFoodCount = 1
                    newStats.zeroFoodTotalProcessingTime = processingTime
                case 1:
                    newStats.oneFoodCount = 1
                    newStats.oneFoodTotalProcessingTime = processingTime
                case 2:
                    newStats.twoFoodCount = 1
                    newStats.twoFoodTotalProcessingTime = processingTime
                default: // 3 or more
                    newStats.multipleFoodCount = 1
                    newStats.multipleFoodTotalProcessingTime = processingTime
                }
            }

            statistics[key] = newStats
        }

        saveStatistics(statistics)
    }

    /// Get statistics for a specific model and request type
    /// - Parameters:
    ///   - model: The AI model
    ///   - requestType: Whether this is image or text
    /// - Returns: Statistics for the model+type, or nil if no data exists
    static func getStatistics(model: AIModel, requestType: RequestType) -> Statistics? {
        let statistics = loadStatistics()
        let key = "\(model.rawValue):\(requestType.rawValue)"
        return statistics[key]
    }

    /// Get all AI provider statistics
    /// - Returns: Array of all tracked statistics, sorted by model key then request type
    static func getAllStatistics() -> [Statistics] {
        let statistics = loadStatistics()
        return statistics.values.sorted { lhs, rhs in
            if lhs.modelKey == rhs.modelKey {
                return lhs.requestType.rawValue < rhs.requestType.rawValue
            }
            return lhs.modelKey < rhs.modelKey
        }
    }

    /// Clear all AI statistics
    static func clearAll() {
        UserDefaults.standard.set(nil, forKey: UserDefaults.AIKey.aiProviderStatistics.rawValue)
    }

    /// Clear statistics for a specific model and request type
    /// - Parameters:
    ///   - model: The AI model
    ///   - requestType: Whether this is image or text
    static func clear(model: AIModel, requestType: RequestType) {
        var statistics = loadStatistics()
        let key = "\(model.rawValue):\(requestType.rawValue)"
        statistics.removeValue(forKey: key)
        saveStatistics(statistics)
    }

    // MARK: - Private Helpers

    private static func loadStatistics() -> [String: Statistics] {
        guard let data = UserDefaults.standard.data(forKey: UserDefaults.AIKey.aiProviderStatistics.rawValue) else {
            return [:]
        }

        let decoder = JSONDecoder()
        do {
            let allStats = try decoder.decode([String: Statistics].self, from: data)

            // Filter out statistics for models that no longer exist
            let validStats = allStats.filter { _, stat in
                // Validate the model still exists
                guard AIModel(rawValue: stat.modelKey) != nil else {
                    return false
                }
                return true
            }

            // If we filtered anything out, save the cleaned version
            if validStats.count != allStats.count {
                saveStatistics(validStats)
            }

            return validStats
        } catch {
            assertionFailure("Unable to decode AI provider statistics: \(error)")
            return [:]
        }
    }

    private static func saveStatistics(_ statistics: [String: Statistics]) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(statistics)
            UserDefaults.standard.set(data, forKey: UserDefaults.AIKey.aiProviderStatistics.rawValue)
        } catch {
            assertionFailure("Unable to encode AI provider statistics: \(error)")
        }
    }
}
