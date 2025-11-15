import Combine
import SwiftUI

class FoodSearchStateModel: ObservableObject {
    @Published var foodSearchText = ""
    @Published var searchResults: [OpenFoodFactsProduct] = []
    @Published var aiSearchResults: [AIFoodItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    init() {
        print("🔍 FoodSearchStateModel initialized")

        $foodSearchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    deinit {
        print("🔍 FoodSearchStateModel deinitialized")
        searchTask?.cancel()
    }

    func performSearch(query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            aiSearchResults = []
            return
        }

        searchTask?.cancel()
        isLoading = true
        errorMessage = nil

        searchTask = Task { @MainActor in
            do {
                let openFoodProducts = try await FoodSearchRouter.shared.searchFoodsByText(query)

                if !Task.isCancelled {
                    self.searchResults = openFoodProducts
                    self.isLoading = false
                    print("✅ Search completed: \(self.searchResults.count) results")
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.searchResults = []
                    print("❌ Search failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func searchWithOpenFoodFacts(barcode: String) {
        isLoading = true
        errorMessage = nil
        foodSearchText = barcode

        Task {
            do {
                print("🔍 Searching OpenFoodFacts for barcode: \(barcode)")

                if let product = try await FoodSearchRouter.shared.searchFoodByBarcode(barcode) {
                    await MainActor.run {
                        self.searchResults = [product]
                        print("✅ OpenFoodFacts found product: \(product.displayName)")
                        self.isLoading = false

                        print("🖼️ Barcode Product URLs: \(product.imageURL ?? "nil"), \(product.imageFrontURL ?? "nil")")
                    }
                } else {
                    await MainActor.run {
                        print("⚠️ No OpenFoodFacts results, using normal search")
                        self.performSearch(query: barcode)
                    }
                }
            } catch {
                await MainActor.run {
                    print("❌ OpenFoodFacts search failed: \(error), using normal search")
                    self.errorMessage = "OpenFoodFacts search failed: \(error.localizedDescription)"
                    self.performSearch(query: barcode)
                }
            }
        }
    }

    func addAISearchResults(_ results: [AIFoodItem]) {
        aiSearchResults = results
    }

    func clearAISearchResults() {
        aiSearchResults = []
    }
}
