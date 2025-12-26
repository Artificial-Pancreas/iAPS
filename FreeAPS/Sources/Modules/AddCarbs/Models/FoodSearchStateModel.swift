import Combine
import SwiftUI

enum FoodSearchRoute: String, Identifiable {
    case camera
    case barcodeScanner
    case aiProgress

    var id: FoodSearchRoute { self }
}

final class FoodSearchStateModel: ObservableObject {
    @Published var foodSearchText = ""
    @Published var isBarcode = false

    @Published var showingFoodSearch = false

    @Published var foodSearchRoute: FoodSearchRoute? = nil

    @Published var aiAnalysisRequest: AnalysisRequest?

    @Published var latestMultipleSelectSearch: FoodItemGroup? = nil
    @Published var savedFoods: FoodItemGroup? = nil
    @Published var latestSearchError: String? = nil
    @Published var latestSearchIcon: String? = nil

    @Published var showSavedFoods = false
    @Published var isLoading = false
    @Published var mealView = false
    @Published var filterText = ""
    @Published var showManualEntry = false
    @Published var showNewSavedFoodEntry = false

    var searchResultsState = SearchResultsState.empty

    // analysis progress

    @Published var isAnalyzing: Bool = false
    @Published var analysisError: String?
//    @Published var showingErrorAlert = false
    @Published var telemetryLogs: [String] = []
    @Published var analysisStart: Date? = nil
    @Published var analysisEnd: Date? = nil
    @Published var analysisEta: TimeInterval?
    @Published var analysisModel: String?

    @Published var searchTask: Task<Void, Never>? = nil

    private var cancellables = Set<AnyCancellable>()

    var foodSearchRouteBinding: Binding<FoodSearchRoute?> {
        Binding(
            get: { [weak self] in
                self?.foodSearchRoute
            },
            set: { [weak self] newValue in
                self?.foodSearchRoute = newValue
            }
        )
    }

    init() {
        searchResultsState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        $foodSearchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self else {
                    return
                }
                let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                self.isBarcode = trimmedQuery.isNotEmpty && isBarcode(trimmedQuery)
            }
            .store(in: &cancellables)
    }

    deinit {
        searchTask?.cancel()
    }

    func enterBarcodeAndSearch(barcode: String) {
        foodSearchText = barcode
        searchByText(query: barcode)
    }

    func startImageAnalysis(image: UIImage) {
        startAIAnalysis(analysisRequest: .image(image))
    }

    func searchByText(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isNotEmpty else {
            return
        }

        let isBarcode = isBarcode(trimmedQuery)

        if isBarcode {
            startBarcodeSearch(barcode: trimmedQuery)
        } else {
            switch UserDefaults.standard.textSearchProvider {
            case .aiModel:
                startAIAnalysis(analysisRequest: .query(trimmedQuery))
            case .openFoodFacts,
                 .usdaFoodData:
                startTextSearch(query: trimmedQuery)
            }
        }
    }

    func retryAIAnalysis() {
        if let request = aiAnalysisRequest {
            startAIAnalysis(analysisRequest: request)
        }
    }

    private func startBarcodeSearch(barcode: String) {
        cancelSearchTask()
        isLoading = true
        latestSearchIcon = "barcode"

        searchTask = Task { @MainActor in
            do {
                let result = try await ConfigurableAIService.shared.analyzeBarcode(
                    barcode,
                    telemetryCallback: nil
                )

                self.isLoading = false
                if !Task.isCancelled {
                    if let first = result.foodItemsDetailed.first {
                        if result.foodItemsDetailed.count == 1 {
                            addItem(first, group: result)
                        } else {
                            self.latestMultipleSelectSearch = result
                        }
                    } else {
                        self.latestSearchError = NSLocalizedString(
                            "Product not found",
                            comment: "barcode search produced no results"
                        )
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.latestSearchError = error.localizedDescription
                    self.isLoading = false
                    print("❌ Search failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func startTextSearch(query: String) {
        cancelSearchTask()
        isLoading = true
        latestSearchIcon = "magnifyingglass"

        searchTask = Task { @MainActor in
            do {
                let result = try await ConfigurableAIService.shared.analyzeFoodQuery(
                    query,
                    telemetryCallback: nil
                )

                self.isLoading = false
                if !Task.isCancelled {
                    if let first = result.foodItemsDetailed.first {
                        if result.foodItemsDetailed.count == 1 {
                            addItem(first, group: result)
                        } else {
                            self.latestMultipleSelectSearch = result
                        }
                    } else {
                        self.latestSearchError = NSLocalizedString(
                            "Product not found",
                            comment: "text database search produced no results"
                        )
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.latestSearchError = error.localizedDescription
                    self.isLoading = false
                    print("❌ Search failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func startAIAnalysis(analysisRequest: AnalysisRequest) {
        cancelSearchTask()
        aiAnalysisRequest = analysisRequest
        analysisStart = Date()
        foodSearchRoute = .aiProgress

        let aiService = ConfigurableAIService.shared

        switch analysisRequest {
        case .image:
            guard aiService.isImageAnalysisConfigured else {
                analysisError = "AI service not configured. Please check settings."
//                showingErrorAlert = true
                return
            }
        case .query:
            guard aiService.isTextSearchConfigured else {
                analysisError = "AI service not configured. Please check settings."
//                showingErrorAlert = true
                return
            }
        }

        searchTask = Task {
            do {
                switch analysisRequest {
                case let .image(image):
                    let result = try await aiService.analyzeFoodImage(image) { telemetryMessage in
                        Task { @MainActor in
                            if telemetryMessage.hasPrefix("ETA: ") {
                                let etaString = telemetryMessage.dropFirst(5)
                                if let etaValue = Double(etaString.trimmingCharacters(in: .whitespaces)) {
                                    self.analysisEta = etaValue * 1.2
                                }
                            } else if telemetryMessage.hasPrefix("MODEL: ") {
                                self.analysisModel = String(telemetryMessage.dropFirst("MODEL: ".count))
                            } else {
                                self.addTelemetryLog(telemetryMessage)
                            }
                        }
                    }
                    await MainActor.run {
                        self.addTelemetryLog("✅ Analysis complete!")
                        self.analysisEnd = Date.now
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.isAnalyzing = false
                            self.onFoodAnalyzed(result, analysisRequest)
                        }
                    }
                case let .query(query):
                    let result = try await aiService.analyzeFoodQuery(query) { telemetryMessage in
                        Task { @MainActor in
                            if telemetryMessage.hasPrefix("ETA: ") {
                                let etaString = telemetryMessage.dropFirst("ETA: ".count)
                                if let etaValue = Double(etaString.trimmingCharacters(in: .whitespaces)) {
                                    self.analysisEta = etaValue * 1.2
                                }
                            } else if telemetryMessage.hasPrefix("MODEL: ") {
                                self.analysisModel = String(telemetryMessage.dropFirst("MODEL: ".count))
                            } else {
                                self.addTelemetryLog(telemetryMessage)
                            }
                        }
                    }
                    await MainActor.run {
                        self.addTelemetryLog("✅ Analysis complete!")
                        self.analysisEnd = Date.now
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.isAnalyzing = false
                            self.onFoodAnalyzed(result, analysisRequest)
                        }
                    }
                }

            } catch {
                await MainActor.run {
                    self.addTelemetryLog("⚠️ Connection interrupted")
                }
                await MainActor.run {
                    self.addTelemetryLog("❌ Analysis failed")

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.isAnalyzing = false
                        self.analysisStart = nil
                        self.analysisEnd = nil
                        self.analysisError = error.localizedDescription
//                        showingErrorAlert = true
                    }
                }
            }
        }
    }

    private func onFoodAnalyzed(
        _ analysisResult: FoodItemGroup,
        _ analysisRequest: AnalysisRequest
    ) {
        if analysisResult.source == .aiMenu {
            latestMultipleSelectSearch = analysisResult
        } else {
            searchResultsState.searchResults = [analysisResult] + searchResultsState.searchResults
        }
        aiAnalysisRequest = analysisRequest
        // TODO: delay before hiding the progress screen, do we want it?
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.foodSearchRoute = nil
        }
    }

    private func addTelemetryLog(_ message: String) {
        telemetryLogs.append(NSLocalizedString(message, comment: "Telemetry log"))
        if telemetryLogs.count > 10 {
            telemetryLogs.removeFirst()
        }
    }

    private func isBarcode(_ str: String) -> Bool {
        let numericCharacterSet = CharacterSet.decimalDigits
        return str.unicodeScalars.allSatisfy { numericCharacterSet.contains($0) }
    }

    func cancelSearchTask() {
        print("cancelling search task")
        searchTask?.cancel()
        searchTask = nil
        latestSearchError = nil
        latestSearchIcon = nil
        latestMultipleSelectSearch = nil
        telemetryLogs = []
        analysisStart = nil
        analysisEnd = nil
        isLoading = false
        isAnalyzing = false
        aiAnalysisRequest = nil
        analysisError = nil
        analysisEnd = nil
        analysisEta = nil
        foodSearchRoute = nil
    }

    func resetNavigationState() {
        foodSearchRoute = nil
    }

    @MainActor func addItem(_ item: FoodItemDetailed, group: FoodItemGroup?) {
        if searchResultsState.isDeleted(item) {
            searchResultsState.undeleteItem(item)
            return
        }

        let targetGroupIndex: Int?
        var targetGroup: FoodItemGroup
        if let group = group, group.source.isAI == true {
            // Find existing group with same ID (for AI sources)
            targetGroupIndex = searchResultsState.searchResults.firstIndex { $0.id == group.id }
            if let targetGroupIndex {
                targetGroup = searchResultsState.searchResults[targetGroupIndex].copyWithItemPrepended(item)
            } else {
                targetGroup = group.copyWithItems([item])
            }
        } else {
            // Find existing group with same source (nil --> manual food entry)
            let source = group?.source ?? .manual
            targetGroupIndex = searchResultsState.searchResults.firstIndex { $0.source == source }
            if let targetGroupIndex {
                targetGroup = searchResultsState.searchResults[targetGroupIndex].copyWithItemPrepended(item)
            } else {
                targetGroup = FoodItemGroup(
                    foodItemsDetailed: [item],
                    source: source,
                )
            }
        }

        if let index = targetGroupIndex {
            searchResultsState.searchResults[index] = targetGroup
            // Move to front if not already there
            if index != 0 {
                searchResultsState.searchResults.remove(at: index)
                searchResultsState.searchResults.insert(targetGroup, at: 0)
            }
        } else {
            searchResultsState.searchResults.insert(targetGroup, at: 0)
        }
    }
}
