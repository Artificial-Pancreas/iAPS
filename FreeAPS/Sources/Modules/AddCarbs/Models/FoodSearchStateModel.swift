import Combine
import SwiftUI

struct AnalysisRoute: Identifiable, Hashable {
    let id = UUID()
    let request: AnalysisRequest

    static func == (lhs: AnalysisRoute, rhs: AnalysisRoute) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

final class FoodSearchStateModel: ObservableObject {
    @Published var foodSearchText = ""
    @Published var isBarcode = false

    @Published var navigateToAIAnalysis: AnalysisRoute? = nil
    @Published var latestTextSearch: FoodAnalysisResult? = nil
    @Published var searchResults: [FoodAnalysisResult] = []
    @Published var aiAnalysisRequest: AnalysisRequest?

    @Published var latestSearchError: String? = nil
    @Published var latestSearchIcon: String? = nil
    @Published var isLoading = false
    @Published var mealView = false
    @Published var navigateToBarcode = false
    @Published var navigateToAICamera = false
    @Published var overrideCameraByDefault = false

    var resultsView = SearchResultsState.empty

    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    init() {
        resultsView.objectWillChange.sink { [weak self] _ in
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

    func searchByText(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isNotEmpty else {
            return
        }
        let isBarcode = isBarcode(trimmedQuery)

        searchTask?.cancel()
        latestSearchError = nil

        searchTask = Task { @MainActor in
            do {
                if isBarcode {
                    self.isLoading = true
                    self.latestSearchIcon = "barcode"
                    let result = try await ConfigurableAIService.shared.analyzeBarcode(
                        trimmedQuery,
                        telemetryCallback: nil
                    )
                    Task { @MainActor in
                        self.isLoading = false
                        if let first = result.foodItemsDetailed.first {
                            if result.foodItemsDetailed.count == 1 {
                                addItem(first)
                            } else {
                                self.latestTextSearch = result
                            }
                        } else {
                            self.latestSearchError = NSLocalizedString(
                                "Product not found",
                                comment: "barcode search produced no results"
                            )
                        }
                    }

                } else {
                    switch UserDefaults.standard.textSearchProvider {
                    case .aiModel:
                        self.isLoading = false
                        self.latestSearchIcon = "brain"
                        navigateToAIAnalysis = AnalysisRoute(request: .query(trimmedQuery))
                        return
                    case .openFoodFacts,
                         .usdaFoodData:
                        self.isLoading = true
                        self.latestSearchIcon = "magnifyingglass"
                        let result = try await ConfigurableAIService.shared.analyzeFoodQuery(
                            trimmedQuery,
                            telemetryCallback: nil
                        )

                        if !Task.isCancelled {
                            self.isLoading = false
                            if let first = result.foodItemsDetailed.first {
                                if result.foodItemsDetailed.count == 1 {
                                    addItem(first)
                                } else {
                                    self.latestTextSearch = result
                                }
                            } else {
                                self.latestSearchError = NSLocalizedString(
                                    "Product not found",
                                    comment: "text database search produced no results"
                                )
                            }
                        }
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

    private func isBarcode(_ str: String) -> Bool {
        let numericCharacterSet = CharacterSet.decimalDigits
        return str.unicodeScalars.allSatisfy { numericCharacterSet.contains($0) }
    }

    func resetNavigationState() {
        navigateToBarcode = false
        navigateToAICamera = false
        navigateToAIAnalysis = nil
        overrideCameraByDefault = false
    }

    @MainActor func addItem(_ item: AnalysedFoodItem) {
        // Early return if source is missing; although caller asserts it won't be nil, guard defensively
        guard let source = item.source else { return }

        // Find an existing result with the same source as the item's source
        if let existingIndex = searchResults.firstIndex(where: { $0.source == source }) {
            let existing = searchResults.remove(at: existingIndex)
            // Build a new items array by prepending the new item
            let newItems = [item] + existing.foodItemsDetailed
            // Rebuild a new FoodAnalysisResult preserving all existing fields, only replacing items
            let updated = FoodAnalysisResult(
                imageType: existing.imageType,
                foodItemsDetailed: newItems,
                briefDescription: existing.briefDescription,
                overallDescription: existing.overallDescription,
                diabetesConsiderations: existing.diabetesConsiderations,
                notes: existing.notes,
                source: existing.source,
                barcode: existing.barcode,
                textQuery: existing.textQuery
            )
            // Put this updated result at the beginning of the list of results
            searchResults.insert(updated, at: 0)
        } else {
            // Create a brand new result for this source; other fields are nil by default
            let newResult = FoodAnalysisResult(
                imageType: nil,
                foodItemsDetailed: [item],
                briefDescription: nil,
                overallDescription: nil,
                diabetesConsiderations: nil,
                notes: nil,
                source: source,
                barcode: nil,
                textQuery: nil
            )
            searchResults.insert(newResult, at: 0)
        }
    }
}
