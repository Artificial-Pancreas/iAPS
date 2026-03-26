import Combine
import Photos
import SwiftUI

@MainActor final class FoodSearchStateModel: ObservableObject {
    @Published var foodSearchText = ""
    @Published var isBarcode = false

    @Published var showingFoodSearch = false

    @Published var foodSearchRoute: FoodSearchRoute? = nil

    @Published var aiAnalysisRequest: AnalysisRequest?

    @Published var latestMultipleSelectSearch: FoodItemGroup? = nil
    @Published var savedFoods: FoodItemGroup? = nil
    @Published var latestSearchError: String? = nil
    @Published var latestSearchIcon: String? = nil

    @Published var showingSettings = false
    @Published var showSavedFoods = false
    @Published var isLoading = false
    @Published var showManualEntry = false
    @Published var showNewSavedFoodEntry = false
    @Published var newFoodEntryToEdit: FoodItemDetailed? = nil

    @Published var aiTextAnalysis = UserDefaults.standard.aiTextSearchByDefault

    @Published var forceShowCommentForNextImage = false

    var searchResultsState = SearchResultsState.empty

    // analysis progress

    @Published var analysisError: String?
    @Published var analysisStart: Date? = nil
    @Published var analysisEnd: Date? = nil
    @Published var analysisEta: TimeInterval?
    @Published var analysisModel: String?

    nonisolated(unsafe) private var searchTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

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
                self.isBarcode = trimmedQuery.isNotEmpty && isStringABarcode(trimmedQuery)
            }
            .store(in: &cancellables)
    }

    deinit {
        searchTask?.cancel()
    }

    func enterBarcodeAndSearch(barcode: String) {
        foodSearchText = barcode
        searchByText(query: barcode, useAI: false)
    }

    func startImageAnalysis(image: UIImage, comment: String?) {
        startAIAnalysis(analysisRequest: .image(image, comment))
    }

    func handleImageCaptured(image: UIImage, fromCamera: Bool) {
        if fromCamera, UserDefaults.standard.aiSavePhotosToLibrary {
            saveImageToLibrary(image)
        }

        let shouldShowComment = forceShowCommentForNextImage || UserDefaults.standard.aiAddImageCommentByDefault

        forceShowCommentForNextImage = false

        if shouldShowComment {
            foodSearchRoute = .imageCommentInput(image)
        } else {
            startImageAnalysis(image: image, comment: nil)
        }
    }

    private func saveImageToLibrary(_ image: UIImage) {
        Task {
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            guard status == .authorized || status == .limited else { return }

            let album = await getOrCreateAlbum(named: "iAPS")
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    if let placeholder = assetRequest.placeholderForCreatedAsset,
                       let album,
                       let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                    {
                        albumChangeRequest.addAssets([placeholder] as NSArray)
                    }
                    // If album is nil, the asset is still saved to the camera roll
                }
            } catch {
                print("❌ Failed to save image: \(error.localizedDescription)")
            }
        }
    }

    private func getOrCreateAlbum(named albumName: String) async -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)

        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        if let album = existing.firstObject { return album }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            }
        } catch {
            print("Failed to create album: \(error.localizedDescription)")
            return nil
        }

        // Fetch by name again — avoids capturing a var placeholder across a @Sendable boundary
        let created = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        return created.firstObject
    }

    func searchByText(query: String, useAI: Bool) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isNotEmpty else {
            return
        }

        let isBarcode = isStringABarcode(trimmedQuery)

        if isBarcode {
            startBarcodeSearch(barcode: trimmedQuery)
        } else if aiTextAnalysis, useAI {
            startAIAnalysis(analysisRequest: .query(trimmedQuery))
        } else {
            startTextSearch(query: trimmedQuery)
        }
    }

    func searchFoodImages(_ query: String) async -> [ImageSearchResult] {
        async let openFoodFacts = OpenFoodFactsService.shared.searchProducts(query: query, pageSize: 15)
        async let openverse = OpenverseClient.shared.searchImages(query: query, pageSize: 15)
        let openFoodFactsResults = (try? await openFoodFacts) ?? []
        let openverseResults = (try? await openverse) ?? []

        let openverseImageResults = openverseResults.compactMap { result -> ImageSearchResult? in
            guard !result.url.isEmpty else { return nil }
            return ImageSearchResult(
                id: UUID().uuidString,
                thumbnailURL: result.thumbnail ?? result.url,
                fullURL: result.url,
                attribution: result.attribution
            )
        }

        let openFoodFactsImageResults = openFoodFactsResults.compactMap { product -> ImageSearchResult? in
            guard let fullURL = product.imageURL ?? product.imageFrontURL else { return nil }
            return ImageSearchResult(
                id: UUID().uuidString,
                thumbnailURL: nil,
                fullURL: fullURL,
                attribution: nil
            )
        }

        return openverseImageResults + openFoodFactsImageResults
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
                let result = try await ConfigurableFoodAnalysisService.shared.analyzeBarcode(
                    barcode,
                    telemetryCallback: nil
                )

                self.isLoading = false
                if !Task.isCancelled {
                    if let first = result.foodItems.first {
                        if result.foodItems.count == 1 {
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
                let result = try await ConfigurableFoodAnalysisService.shared.executeTextSearch(
                    query,
                    telemetryCallback: nil
                )

                self.isLoading = false
                if !Task.isCancelled {
                    if let first = result.foodItems.first {
                        if result.foodItems.count == 1 {
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

        let aiService = ConfigurableFoodAnalysisService.shared

        switch analysisRequest {
        case .image:
            guard aiService.isImageAnalysisConfigured else {
                analysisError = "AI service not configured. Please check settings."
                return
            }
        case .query:
            guard aiService.isAiTextAnalysisConfigured else {
                analysisError = "AI service not configured. Please check settings."
                return
            }
        }

        searchTask = Task { @MainActor in
            let telemetry: @Sendable(String) -> Void = { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.handleTelemetry(message)
                }
            }
            do {
                let result = switch analysisRequest {
                case let .image(image, comment): try await aiService
                    .analyzeFoodImage(image, comment: comment, telemetryCallback: telemetry)
                case let .query(query): try await aiService.analyzeFoodQuery(query, telemetryCallback: telemetry)
                }
                self.analysisEnd = Date.now
                // TODO: delay before hiding the progress screen, do we want it?
                try? await Task.sleep(for: .seconds(1))
                if result.source == .aiMenu {
                    latestMultipleSelectSearch = result
                } else {
                    searchResultsState.searchResults = [result] + searchResultsState.searchResults
                }
                foodSearchRoute = nil
            } catch is CancellationError {
                // cancelled, already reset by cancelSearchTask()
            } catch {
                try? await Task.sleep(for: .seconds(1))
                self.analysisStart = nil
                self.analysisEnd = nil
                self.analysisError = error.localizedDescription
            }
        }
    }

    private func handleTelemetry(_ message: String) {
        if message.hasPrefix("ETA: "),
           let eta = Double(message.dropFirst("ETA: ".count).trimmingCharacters(in: .whitespaces))
        {
            analysisEta = eta * 1.2
        } else if message.hasPrefix("MODEL: ") {
            analysisModel = String(message.dropFirst("MODEL: ".count))
        }
    }

    private func isStringABarcode(_ str: String) -> Bool {
        let numericCharacterSet = CharacterSet.decimalDigits
        return str.unicodeScalars.allSatisfy { numericCharacterSet.contains($0) }
    }

    func cancelSearchTask() {
        searchTask?.cancel()
        searchTask = nil
        latestSearchError = nil
        latestSearchIcon = nil
        latestMultipleSelectSearch = nil
        analysisStart = nil
        analysisEnd = nil
        isLoading = false
        aiAnalysisRequest = nil
        analysisError = nil
        analysisEta = nil
        foodSearchRoute = nil
    }

    func addItem(_ item: FoodItemDetailed, group: FoodItemGroup?) {
        if item.deleted {
            searchResultsState.undeleteItem(item)
            return
        }

        let targetGroupIndex: Int?
        var targetGroup: FoodItemGroup
        if let group = group, group.source.isAI {
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
                    foodItems: [item],
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
