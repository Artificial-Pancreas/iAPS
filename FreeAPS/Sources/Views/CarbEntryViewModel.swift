import Combine
import HealthKit
import LoopKit
import ObjectiveC
import os.log
import SwiftUI
import Swinject
import UIKit

// iAPS-spezifische Konstanten definieren
struct iAPSConstants {
    static let maxCarbEntryQuantity = HKQuantity(unit: .gram(), doubleValue: 1000)
    static let warningCarbEntryQuantity = HKQuantity(unit: .gram(), doubleValue: 250)
    static let minCarbAbsorptionTime = TimeInterval(30 * 60) // 30 Minuten
    static let maxCarbAbsorptionTime = TimeInterval(8 * 60 * 60) // 8 Stunden
    static let maxCarbEntryPastTime = TimeInterval(-24 * 60 * 60) // 24 Stunden in die Vergangenheit
    static let maxCarbEntryFutureTime = TimeInterval(60 * 60) // 1 Stunde in die Zukunft
}

// MARK: - Timeout Utilities

/// Error thrown when an operation times out
struct TimeoutError: Error {
    let duration: TimeInterval

    var localizedDescription: String {
        "Operation timed out after \(duration) seconds"
    }
}

/// Execute an async operation with a timeout
/// - Parameters:
///   - seconds: Timeout duration in seconds
///   - operation: The async operation to execute
/// - Throws: TimeoutError if the operation doesn't complete within the timeout
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation
        group.addTask {
            try await operation()
        }

        // Add the timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError(duration: seconds)
        }

        // Return the first result and cancel the other task
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// Protokoll für den Delegate - muss an iAPS angepasst werden
protocol CarbEntryViewModelDelegate: AnyObject {
    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes { get }
    var analyticsServicesManager: AnalyticsService? { get }
    // Weitere iAPS-spezifische Properties hier hinzufügen
}

final class CarbEntryViewModel: ObservableObject {
    enum Alert: Identifiable {
        var id: Self {
            self
        }

        case maxQuantityExceded
        case warningQuantityValidation
    }

    enum Warning: Identifiable {
        var id: Self {
            self
        }

        var priority: Int {
            switch self {
            case .entryIsMissedMeal:
                return 1
            case .overrideInProgress:
                return 2
            }
        }

        case entryIsMissedMeal
        case overrideInProgress
    }

    @Published var alert: CarbEntryViewModel.Alert?
    @Published var warnings: Set<Warning> = []

    @Published var bolusViewModel: Bolus?

    let shouldBeginEditingQuantity: Bool

    @Published var carbsQuantity: Double? = nil
    var preferredCarbUnit = HKUnit.gram()
    var maxCarbEntryQuantity = iAPSConstants.maxCarbEntryQuantity
    var warningCarbEntryQuantity = iAPSConstants.warningCarbEntryQuantity

    @Published var time = Date()
    private var date = Date()
    var minimumDate: Date { date.addingTimeInterval(iAPSConstants.maxCarbEntryPastTime) }
    var maximumDate: Date { date.addingTimeInterval(iAPSConstants.maxCarbEntryFutureTime) }

    @Published var foodType = ""
    @Published var selectedDefaultAbsorptionTimeEmoji: String = ""
    @Published var usesCustomFoodType = false
    @Published var absorptionTimeWasEdited = false
    @Published var absorptionTimeWasAIGenerated = false
    internal var absorptionEditIsProgrammatic = false

    @Published var absorptionTime: TimeInterval
    let defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes
    let minAbsorptionTime = iAPSConstants.minCarbAbsorptionTime
    let maxAbsorptionTime = iAPSConstants.maxCarbAbsorptionTime
    var absorptionTimesRange: ClosedRange<TimeInterval> {
        minAbsorptionTime ... maxAbsorptionTime
    }

    @Published var selectedFavoriteFoodIndex = -1

    // MARK: - Food Search Properties

    @Published var foodSearchText: String = ""
    @Published var foodSearchResults: [OpenFoodFactsProduct] = []
    @Published var selectedFoodProduct: OpenFoodFactsProduct? = nil
    @Published var selectedFoodServingSize: String? = nil
    @Published var numberOfServings: Double = 1.0
    @Published var isFoodSearching: Bool = false
    @Published var foodSearchError: String? = nil
    @Published var showingFoodSearch: Bool = false
    @Published var lastAIAnalysisResult: AIFoodAnalysisResult? = nil
    @Published var capturedAIImage: UIImage? = nil

    private var lastBarcodeSearched: String?
    private var observersSetUp = false
    private var searchCache: [String: CachedSearchResult] = [:]
    private let openFoodFactsService = OpenFoodFactsService()
    private let aiService = ConfigurableAIService.shared
    weak var delegate: CarbEntryViewModelDelegate?
    private lazy var cancellables = Set<AnyCancellable>()

    private struct CachedSearchResult {
        let results: [OpenFoodFactsProduct]
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300 // 5 minutes cache
        }
    }

    /// Initalizer for when`CarbEntryView` is presented from the home screen
    init(delegate: CarbEntryViewModelDelegate) {
        self.delegate = delegate
        absorptionTime = delegate.defaultAbsorptionTimes.medium
        defaultAbsorptionTimes = delegate.defaultAbsorptionTimes
        shouldBeginEditingQuantity = true

        observeAbsorptionTimeChange()
        observeFavoriteFoodIndexChange()
        observeNumberOfServingsChange()
        setupFoodSearchObservers()
    }

    /// Initalizer for when`CarbEntryView` has an entry to edit
    init(delegate: CarbEntryViewModelDelegate, originalCarbEntry: StoredCarbEntry) {
        self.delegate = delegate
        self.originalCarbEntry = originalCarbEntry
        defaultAbsorptionTimes = delegate.defaultAbsorptionTimes

        carbsQuantity = originalCarbEntry.quantity.doubleValue(for: preferredCarbUnit)
        time = originalCarbEntry.startDate
        foodType = originalCarbEntry.foodType ?? ""
        absorptionTime = originalCarbEntry.absorptionTime ?? .hours(3)
        absorptionTimeWasEdited = true
        usesCustomFoodType = true
        shouldBeginEditingQuantity = false

        observeAbsorptionTimeChange()
        observeFavoriteFoodIndexChange()
        observeNumberOfServingsChange()
        setupFoodSearchObservers()
    }

    var originalCarbEntry: StoredCarbEntry?

    private var updatedCarbEntry: NewCarbEntry? {
        if let quantity = carbsQuantity, quantity != 0 {
            if let o = originalCarbEntry, o.quantity.doubleValue(for: preferredCarbUnit) == quantity, o.startDate == time,
               o.foodType == foodType, o.absorptionTime == absorptionTime
            {
                return nil // No changes were made
            }

            return NewCarbEntry(
                date: date,
                quantity: HKQuantity(unit: preferredCarbUnit, doubleValue: quantity),
                startDate: time,
                foodType: usesCustomFoodType ? foodType : selectedDefaultAbsorptionTimeEmoji,
                absorptionTime: absorptionTime
            )
        } else {
            return nil
        }
    }

    var saveFavoriteFoodButtonDisabled: Bool {
        if let carbsQuantity, 0 ... maxCarbEntryQuantity.doubleValue(for: preferredCarbUnit) ~= carbsQuantity,
           selectedFavoriteFoodIndex == -1
        {
            return false
        }
        return true
    }

    var continueButtonDisabled: Bool { updatedCarbEntry == nil }

    // MARK: - Continue to Bolus and Carb Quantity Warnings

    func continueToBolus() {
        guard updatedCarbEntry != nil else {
            return
        }
        validateInputAndContinue()
    }

    private func validateInputAndContinue() {
        guard absorptionTime <= maxAbsorptionTime else {
            return
        }

        guard let carbsQuantity, carbsQuantity > 0 else { return }
        let quantity = HKQuantity(unit: preferredCarbUnit, doubleValue: carbsQuantity)
        if quantity.compare(maxCarbEntryQuantity) == .orderedDescending {
            alert = .maxQuantityExceded
            return
        } else if quantity.compare(warningCarbEntryQuantity) == .orderedDescending, selectedFavoriteFoodIndex == -1 {
            alert = .warningQuantityValidation
            return
        }

        Task { @MainActor in
            setBolusViewModel()
        }
    }

    protocol CarbEntryViewModelDelegate: AnyObject {
        var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes { get }
        var analyticsServicesManager: AnalyticsService? { get }
        var resolver: Resolver { get } // Hinzufügen
    }

    @MainActor private func setBolusViewModel() {
        // iAPS-spezifische Bolus-Erstellung
        guard let resolver = delegate?.resolver else {
            print("Error: Resolver not available")
            return
        }

        // Speichere zuerst die Carbs in der iAPS CarbsStorage
        if let carbEntry = updatedCarbEntry {
            saveCarbsToStorage(carbEntry: carbEntry, resolver: resolver)
        }

        // Erstelle die Bolus RootView mit den notwendigen Parametern
        let bolusView = Bolus.RootView(
            resolver: resolver,
            waitForSuggestion: true,
            fetch: true
        )

        // Zeige den Bolus-View an using iAPS modal system
        showBolusModal(bolusView)

        // delegate?.analyticsServicesManager?.didDisplayBolusScreen()
    }

    private func saveCarbsToStorage(carbEntry: NewCarbEntry, resolver: Resolver) {
        guard let carbsStorage = resolver.resolve(CarbsStorage.self) else {
            print("Error: CarbsStorage not available")
            return
        }

        let carbs = carbEntry.quantity.doubleValue(for: .gram())
        let foodType = carbEntry.foodType ?? ""

        let iAPSCarbsEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: carbEntry.startDate,
            actualDate: carbEntry.startDate,
            carbs: Decimal(carbs),
            fat: nil,
            protein: nil,
            note: foodType,
            enteredBy: CarbsEntry.manual,
            isFPU: nil
        )

        // Speichere die Carbs in der iAPS Storage
        carbsStorage.storeCarbs([iAPSCarbsEntry])

        // Setze die temporären Daten für den Bolus-View über die iAPS Methode
        setTemporaryDataForBolus(carbs: carbs, foodType: foodType, date: carbEntry.startDate, resolver: resolver)
    }

    private func setTemporaryDataForBolus(carbs: Double, foodType: String, date: Date, resolver: Resolver) {
        // iAPS verwendet wahrscheinlich eine andere Methode um temporäre Daten zu setzen
        // Basierend auf dem StateModel-Code scheint es carbToStore zu verwenden

        if let stateModel = resolver.resolve(Bolus.StateModel.self) {
            // Erstelle eine CarbsEntry für den StateModel
            let tempCarbsEntry = CarbsEntry(
                id: UUID().uuidString,
                createdAt: date,
                actualDate: date,
                carbs: Decimal(carbs),
                fat: nil,
                protein: nil,
                note: foodType,
                enteredBy: CarbsEntry.manual,
                isFPU: nil
            )

            // Setze die carbToStore im StateModel
            stateModel.carbToStore = [tempCarbsEntry]
            stateModel.carbs = Decimal(carbs)
            stateModel.note = foodType
        }
    }

    private func showBolusModal(_ view: Bolus.RootView) {
        // iAPS verwendet wahrscheinlich einen eigenen Modal-Mechanismus
        if let window = UIApplication.shared.windows.first,
           let rootViewController = window.rootViewController
        {
            let hostingController = UIHostingController(rootView: view)
            hostingController.modalPresentationStyle = .formSheet

            if let presentedVC = rootViewController.presentedViewController {
                presentedVC.present(hostingController, animated: true)
            } else {
                rootViewController.present(hostingController, animated: true)
            }
        }
    }

    func clearAlert() {
        alert = nil
    }

    func clearAlertAndContinueToBolus() {
        alert = nil
        Task { @MainActor in
            setBolusViewModel()
        }
    }

    // MARK: - Favorite Foods

    private func observeFavoriteFoodIndexChange() {
        $selectedFavoriteFoodIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] index in
                self?.favoriteFoodSelected(at: index)
            }
            .store(in: &cancellables)
    }

    func manualFavoriteFoodSelected(at index: Int) {
        favoriteFoodSelected(at: index)
    }

    private func favoriteFoodSelected(at index: Int) {
        absorptionEditIsProgrammatic = true
        if index == -1 {
            carbsQuantity = 0
            foodType = ""
            absorptionTime = defaultAbsorptionTimes.medium
            absorptionTimeWasEdited = false
            absorptionTimeWasAIGenerated = false
            usesCustomFoodType = false
        } else {
            absorptionTimeWasEdited = true
            absorptionTimeWasAIGenerated = false
            usesCustomFoodType = true
        }
    }

    // MARK: - Utility

    func restoreUserActivityState(_ activity: NSUserActivity) {
        if let entry = activity.newCarbEntry {
            time = entry.date
            carbsQuantity = entry.quantity.doubleValue(for: preferredCarbUnit)

            if let foodType = entry.foodType {
                self.foodType = foodType
                usesCustomFoodType = true
            }

            if let absorptionTime = entry.absorptionTime {
                self.absorptionTime = absorptionTime
                absorptionTimeWasEdited = true
            }

            if activity.entryisMissedMeal {
                warnings.insert(.entryIsMissedMeal)
            }
        }
    }

    /*   private func observeLoopUpdates() {
         checkIfOverrideEnabled()
         NotificationCenter.default
             .publisher(for: .LoopDataUpdated)
             .receive(on: DispatchQueue.main)
             .sink { [weak self] _ in
                 self?.checkIfOverrideEnabled()
             }
             .store(in: &cancellables)
     }*/

    private func checkIfOverrideEnabled() {
        // iAPS-spezifische Override-Logik hier implementieren
        // Diese Funktion muss an iAPS angepasst werden
        warnings.remove(.overrideInProgress)
    }

    private func observeAbsorptionTimeChange() {
        $absorptionTime
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in
                if self?.absorptionEditIsProgrammatic == true {
                    self?.absorptionEditIsProgrammatic = false
                } else {
                    self?.absorptionTimeWasEdited = true
                    self?.absorptionTimeWasAIGenerated = false
                }
            }
            .store(in: &cancellables)
    }

    private func observeNumberOfServingsChange() {
        $numberOfServings
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] servings in
                self?.recalculateCarbsForServings(servings)
            }
            .store(in: &cancellables)
    }
}

// MARK: - OpenFoodFacts Food Search Extension

extension CarbEntryViewModel {
    private var foodSearchTask: Task<Void, Never>? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.foodSearchTask) as? Task<Void, Never> }
        set { objc_setAssociatedObject(self, &AssociatedKeys.foodSearchTask, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    private enum AssociatedKeys {
        static var foodSearchTask: UInt8 = 0
    }

    // MARK: - Food Search Methods

    func setupFoodSearchObservers() {
        guard !observersSetUp else { return }
        observersSetUp = true
        cancellables.removeAll()

        $foodSearchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] searchText in
                self?.performFoodSearch(query: searchText)
            }
            .store(in: &cancellables)

        // iAPS-spezifischer Barcode-Scanner Service hier anpassen
        /*
         BarcodeScannerService.shared.$lastScanResult
             .compactMap { $0 }
             .removeDuplicates { $0.barcodeString == $1.barcodeString }
             .throttle(for: .milliseconds(800), scheduler: DispatchQueue.main, latest: false)
             .sink { [weak self] result in
                 self?.searchFoodProductByBarcode(result.barcodeString)
             }
             .store(in: &cancellables)
         */
    }

    func performFoodSearch(query: String) {
        foodSearchTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            foodSearchResults = []
            foodSearchError = nil
            showingFoodSearch = false
            return
        }

        showingFoodSearch = true
        foodSearchResults = []
        foodSearchError = nil
        isFoodSearching = true

        foodSearchTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                await self.searchFoodProducts(query: trimmedQuery)
            } catch {
                await MainActor.run {
                    self.foodSearchError = error.localizedDescription
                    self.isFoodSearching = false
                }
            }
        }
    }

    @MainActor private func searchFoodProducts(query: String) async {
        print("🔍 searchFoodProducts starting for: '\(query)'")
        print("🔍 DEBUG: isFoodSearching at start: \(isFoodSearching)")
        foodSearchError = nil

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Check cache first for instant results
        if let cachedResult = searchCache[trimmedQuery], !cachedResult.isExpired {
            print("🔍 Using cached results for: '\(trimmedQuery)'")
            foodSearchResults = cachedResult.results
            isFoodSearching = false
            return
        }

        // Show skeleton loading state immediately
        foodSearchResults = createSkeletonResults()

        let searchStartTime = Date()
        let minimumSearchDuration: TimeInterval = 0.3

        do {
            print("🔍 Performing text search with configured provider...")
            let products = try await performTextSearch(query: query)

            // Cache the results for future use
            searchCache[trimmedQuery] = CachedSearchResult(results: products, timestamp: Date())
            print("🔍 Cached results for: '\(trimmedQuery)' (\(products.count) items)")

            // Periodically clean up expired cache entries
            if searchCache.count > 20 {
                cleanupExpiredCache()
            }

            // Ensure minimum search duration for smooth animations
            let elapsedTime = Date().timeIntervalSince(searchStartTime)
            if elapsedTime < minimumSearchDuration {
                let remainingTime = minimumSearchDuration - elapsedTime
                print("🔍 Adding \(remainingTime)s delay to reach minimum search duration")
                do {
                    try await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
                } catch {
                    // Task.sleep can throw CancellationError, which is fine to ignore for timing
                    print("🔍 Task.sleep cancelled during search timing (expected)")
                }
            }

            foodSearchResults = products

            print("🔍 Search completed! Found \(products.count) products")

        } catch {
            print("🔍 Search failed with error: \(error)")

            // Don't show cancellation errors to the user - they're expected during rapid typing
            if let cancellationError = error as? CancellationError {
                print("🔍 Search was cancelled (expected behavior)")
                // Clear any previous error when cancelled
                foodSearchError = nil
                isFoodSearching = false
                return
            }

            // Check for URLError cancellation as well
            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("🔍 URLSession request was cancelled (expected behavior)")
                // Clear any previous error when cancelled
                foodSearchError = nil
                isFoodSearching = false
                return
            }

            // Check for OpenFoodFactsError wrapping a URLError cancellation
            if let openFoodFactsError = error as? OpenFoodFactsError,
               case let .networkError(underlyingError) = openFoodFactsError,
               let urlError = underlyingError as? URLError,
               urlError.code == .cancelled
            {
                print("🔍 OpenFoodFacts wrapped URLSession request was cancelled (expected behavior)")
                // Clear any previous error when cancelled
                foodSearchError = nil
                isFoodSearching = false
                return
            }

            // For real errors, ensure minimum search duration before showing error
            let elapsedTime = Date().timeIntervalSince(searchStartTime)
            if elapsedTime < minimumSearchDuration {
                let remainingTime = minimumSearchDuration - elapsedTime
                print("🔍 Adding \(remainingTime)s delay before showing error")
                do {
                    try await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
                } catch {
                    // Task.sleep can throw CancellationError, which is fine to ignore for timing
                    print("🔍 Task.sleep cancelled during error timing (expected)")
                }
            }

            foodSearchError = error.localizedDescription
            foodSearchResults = []
        }

        // Always set isFoodSearching to false at the end
        isFoodSearching = false
        print("🔍 searchFoodProducts finished, isFoodSearching = false")
        print("🔍 DEBUG: Final results count: \(foodSearchResults.count)")
    }

    func searchFoodProductByBarcode(_ barcode: String) {
        if let lastBarcode = lastBarcodeSearched, lastBarcode == barcode {
            return
        }

        foodSearchTask?.cancel()
        lastBarcodeSearched = barcode

        foodSearchTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await withTimeout(seconds: 45) {
                    await self.lookupProductByBarcode(barcode)
                }
                await MainActor.run {
                    self.lastBarcodeSearched = nil
                }
            } catch {
                await MainActor.run {
                    if error is TimeoutError {
                        self.createManualEntryPlaceholder(for: barcode)
                        self.lastBarcodeSearched = nil
                        return
                    }
                    self.foodSearchError = error.localizedDescription
                    self.isFoodSearching = false
                    self.lastBarcodeSearched = nil
                }
            }
        }
    }

    @MainActor private func lookupProductByBarcode(_ barcode: String) async {
        foodSearchResults = []
        isFoodSearching = true
        foodSearchError = nil

        defer {
            isFoodSearching = false
        }

        do {
            if let product = try await performBarcodeSearch(barcode: barcode) {
                if !foodSearchResults.contains(product) {
                    foodSearchResults.insert(product, at: 0)
                }
                selectFoodProduct(product)
            } else {
                createManualEntryPlaceholder(for: barcode)
            }
        } catch {
            createManualEntryPlaceholder(for: barcode)
        }
    }

    private func createManualEntryPlaceholder(for barcode: String) {
        let fallbackProduct = OpenFoodFactsProduct(
            id: "fallback_\(barcode)",
            productName: "Product \(barcode)",
            brands: "Database Unavailable",
            categories: "⚠️ NUTRITION DATA UNAVAILABLE - ENTER MANUALLY",
            nutriments: Nutriments(
                carbohydrates: 0.0,
                proteins: 0.0,
                fat: 0.0,
                calories: 0.0,
                sugars: nil,
                fiber: nil
            ),
            servingSize: "Enter serving size",
            servingQuantity: 100.0,
            imageURL: nil,
            imageFrontURL: nil,
            code: barcode,
            dataSource: .barcodeScan
        )

        if !foodSearchResults.contains(fallbackProduct) {
            foodSearchResults.insert(fallbackProduct, at: 0)
        }

        selectFoodProduct(fallbackProduct)
        foodSearchError = nil
    }

    func selectFoodProduct(_ product: OpenFoodFactsProduct) {
        selectedFoodProduct = product

        let maxFoodTypeLength = 20
        if product.displayName.count > maxFoodTypeLength {
            let truncatedName = String(product.displayName.prefix(maxFoodTypeLength - 1)) + "…"
            foodType = truncatedName
        } else {
            foodType = product.displayName
        }
        usesCustomFoodType = true

        selectedFoodServingSize = product.servingSizeDisplay
        numberOfServings = 1.0

        if product.id.hasPrefix("fallback_") {
            carbsQuantity = nil
        } else if let carbsPerServing = product.carbsPerServing {
            carbsQuantity = carbsPerServing * numberOfServings
        } else if product.nutriments.carbohydrates > 0 {
            carbsQuantity = product.nutriments.carbohydrates * numberOfServings
        } else {
            carbsQuantity = nil
        }

        foodSearchText = ""
        foodSearchResults = []
        foodSearchError = nil
        showingFoodSearch = false
        foodSearchTask?.cancel()

        if !product.id.hasPrefix("ai_") {
            lastAIAnalysisResult = nil
            capturedAIImage = nil
            absorptionTimeWasAIGenerated = false
        }
    }

    private func recalculateCarbsForServings(_ servings: Double) {
        guard let selectedFood = selectedFoodProduct else { return }

        if let carbsPerServing = selectedFood.carbsPerServing {
            carbsQuantity = carbsPerServing * servings
        } else {
            carbsQuantity = selectedFood.nutriments.carbohydrates * servings
        }
    }

    private func createSkeletonResults() -> [OpenFoodFactsProduct] {
        (0 ..< 3).map { index in
            var product = OpenFoodFactsProduct(
                id: "skeleton_\(index)",
                productName: "Loading...",
                brands: "Loading...",
                categories: nil,
                nutriments: Nutriments.empty(),
                servingSize: nil,
                servingQuantity: nil,
                imageURL: nil,
                imageFrontURL: nil,
                code: nil,
                dataSource: .unknown,
                isSkeleton: false
            )
            product.isSkeleton = true
            return product
        }
    }

    func clearFoodSearch() {
        foodSearchText = ""
        foodSearchResults = []
        selectedFoodProduct = nil
        selectedFoodServingSize = nil
        foodSearchError = nil
        showingFoodSearch = false
        foodSearchTask?.cancel()
        lastBarcodeSearched = nil
    }

    private func cleanupExpiredCache() {
        let expiredKeys = searchCache.compactMap { key, value in
            value.isExpired ? key : nil
        }
        for key in expiredKeys {
            searchCache.removeValue(forKey: key)
        }
    }

    func clearSearchCache() {
        searchCache.removeAll()
    }

    func toggleFoodSearch() {
        showingFoodSearch.toggle()
        if !showingFoodSearch {
            clearFoodSearch()
        }
    }

    func clearSelectedFood() {
        selectedFoodProduct = nil
        selectedFoodServingSize = nil
        numberOfServings = 1.0
        lastAIAnalysisResult = nil
        capturedAIImage = nil
        absorptionTimeWasAIGenerated = false
        lastBarcodeSearched = nil
        carbsQuantity = nil
        foodType = ""
        usesCustomFoodType = false
    }

    // MARK: - Provider Routing Methods

    private func performTextSearch(query: String) async throws -> [OpenFoodFactsProduct] {
        let provider = aiService.getProviderForSearchType(.textSearch)

        switch provider {
        case .openFoodFacts:
            let products = try await openFoodFactsService.searchProducts(query: query, pageSize: 15)
            return products.map { product in
                OpenFoodFactsProduct(
                    id: product.id,
                    productName: product.productName,
                    brands: product.brands,
                    categories: product.categories,
                    nutriments: product.nutriments,
                    servingSize: product.servingSize,
                    servingQuantity: product.servingQuantity,
                    imageURL: product.imageURL,
                    imageFrontURL: product.imageFrontURL,
                    code: product.code,
                    dataSource: .textSearch
                )
            }

        case .usdaFoodData:
            let products = try await USDAFoodDataService.shared.searchProducts(query: query, pageSize: 15)
            return products.map { product in
                OpenFoodFactsProduct(
                    id: product.id,
                    productName: product.productName,
                    brands: product.brands,
                    categories: product.categories,
                    nutriments: product.nutriments,
                    servingSize: product.servingSize,
                    servingQuantity: product.servingQuantity,
                    imageURL: product.imageURL,
                    imageFrontURL: product.imageFrontURL,
                    code: product.code,
                    dataSource: .textSearch
                )
            }

       /* case .claude:
            return try await searchWithClaude(query: query)

        case .googleGemini:
            return try await searchWithGoogleGemini(query: query)*/

        case .claude,
             .googleGemini:
            // Fallback to OpenFoodFacts for now
            let products = try await openFoodFactsService.searchProducts(query: query, pageSize: 15)
            return products.map { product in
                OpenFoodFactsProduct(
                    id: product.id,
                    productName: product.productName,
                    brands: product.brands,
                    categories: product.categories,
                    nutriments: product.nutriments,
                    servingSize: product.servingSize,
                    servingQuantity: product.servingQuantity,
                    imageURL: product.imageURL,
                    imageFrontURL: product.imageFrontURL,
                    code: product.code,
                    dataSource: .textSearch
                )
            }

        case .openAI:
            let products = try await openFoodFactsService.searchProducts(query: query, pageSize: 15)
            return products.map { product in
                OpenFoodFactsProduct(
                    id: product.id,
                    productName: product.productName,
                    brands: product.brands,
                    categories: product.categories,
                    nutriments: product.nutriments,
                    servingSize: product.servingSize,
                    servingQuantity: product.servingQuantity,
                    imageURL: product.imageURL,
                    imageFrontURL: product.imageFrontURL,
                    code: product.code,
                    dataSource: .textSearch
                )
            }
        }
    }

    private func performBarcodeSearch(barcode: String) async throws -> OpenFoodFactsProduct? {
        let provider = aiService.getProviderForSearchType(.barcodeSearch)

        switch provider {
        case .openFoodFacts:
            if let product = try await openFoodFactsService.fetchProduct(barcode: barcode) {
                return OpenFoodFactsProduct(
                    id: product.id,
                    productName: product.productName,
                    brands: product.brands,
                    categories: product.categories,
                    nutriments: product.nutriments,
                    servingSize: product.servingSize,
                    servingQuantity: product.servingQuantity,
                    imageURL: product.imageURL,
                    imageFrontURL: product.imageFrontURL,
                    code: product.code,
                    dataSource: .barcodeScan
                )
            }
            return nil

        case .claude,
             .googleGemini,
             .openAI,
             .usdaFoodData:
            // These providers don't support barcode search, fall back to OpenFoodFacts
            if let product = try await openFoodFactsService.fetchProduct(barcode: barcode) {
                // Create a new product with the correct dataSource
                return OpenFoodFactsProduct(
                    id: product.id,
                    productName: product.productName,
                    brands: product.brands,
                    categories: product.categories,
                    nutriments: product.nutriments,
                    servingSize: product.servingSize,
                    servingQuantity: product.servingQuantity,
                    imageURL: product.imageURL,
                    imageFrontURL: product.imageFrontURL,
                    code: product.code,
                    dataSource: .barcodeScan
                )
            }
            return nil

        default:
            if let product = try await openFoodFactsService.fetchProduct(barcode: barcode) {
                return OpenFoodFactsProduct(
                    id: product.id,
                    productName: product.productName,
                    brands: product.brands,
                    categories: product.categories,
                    nutriments: product.nutriments,
                    servingSize: product.servingSize,
                    servingQuantity: product.servingQuantity,
                    imageURL: product.imageURL,
                    imageFrontURL: product.imageFrontURL,
                    code: product.code,
                    dataSource: .barcodeScan
                )
            }
            return nil
        }
    }

    // Weitere Hilfsmethoden für Claude, Gemini etc. bleiben ähnlich...
    // Diese müssen ebenfalls an iAPS angepasst werden

    // MARK: - Food Item Management

    func deleteFoodItem(at index: Int) {
        guard var currentResult = lastAIAnalysisResult,
              index >= 0, index < currentResult.foodItemsDetailed.count
        else {
            return
        }

        currentResult.foodItemsDetailed.remove(at: index)

        let newTotalCarbs = currentResult.foodItemsDetailed.reduce(0) { $0 + $1.carbohydrates }
        let newTotalProtein = currentResult.foodItemsDetailed.compactMap(\.protein).reduce(0, +)
        let newTotalFat = currentResult.foodItemsDetailed.compactMap(\.fat).reduce(0, +)
        let newTotalFiber = currentResult.foodItemsDetailed.compactMap(\.fiber).reduce(0, +)
        let newTotalCalories = currentResult.foodItemsDetailed.compactMap(\.calories).reduce(0, +)

        currentResult.totalCarbohydrates = newTotalCarbs
        currentResult.totalProtein = newTotalProtein > 0 ? newTotalProtein : nil
        currentResult.totalFat = newTotalFat > 0 ? newTotalFat : nil
        currentResult.totalFiber = newTotalFiber > 0 ? newTotalFiber : nil
        currentResult.totalCalories = newTotalCalories > 0 ? newTotalCalories : nil

        if UserDefaults.standard.advancedDosingRecommendationsEnabled {
            let (newAbsorptionHours, newReasoning) = recalculateAbsorptionTime(
                carbs: newTotalCarbs,
                protein: newTotalProtein,
                fat: newTotalFat,
                fiber: newTotalFiber,
                calories: newTotalCalories,
                remainingItems: currentResult.foodItemsDetailed
            )

            currentResult.absorptionTimeHours = newAbsorptionHours
            currentResult.absorptionTimeReasoning = newReasoning

            if absorptionTimeWasAIGenerated {
                let newAbsorptionTimeInterval = TimeInterval(newAbsorptionHours * 3600)
                absorptionEditIsProgrammatic = true
                absorptionTime = newAbsorptionTimeInterval
            }
        }

        lastAIAnalysisResult = currentResult
        carbsQuantity = newTotalCarbs
    }

    // MARK: - Absorption Time Recalculation

    private func recalculateAbsorptionTime(
        carbs: Double,
        protein: Double,
        fat: Double,
        fiber: Double,
        calories: Double,
        remainingItems _: [FoodItemAnalysis]
    ) -> (hours: Double, reasoning: String) {
        let baselineHours: Double = carbs <= 15 ? 2.5 : 3.0
        let fpuValue = (fat + protein) / 10.0
        let fpuAdjustment: Double
        let fpuDescription: String

        if fpuValue < 2.0 {
            fpuAdjustment = 1.0
            fpuDescription = "Low FPU (\(String(format: "%.1f", fpuValue))) - minimal extension"
        } else if fpuValue < 4.0 {
            fpuAdjustment = 2.5
            fpuDescription = "Medium FPU (\(String(format: "%.1f", fpuValue))) - moderate extension"
        } else {
            fpuAdjustment = 4.0
            fpuDescription = "High FPU (\(String(format: "%.1f", fpuValue))) - significant extension"
        }

        let fiberAdjustment: Double
        let fiberDescription: String

        if fiber > 8.0 {
            fiberAdjustment = 2.0
            fiberDescription = "High fiber (\(String(format: "%.1f", fiber))g) - significantly slows absorption"
        } else if fiber > 5.0 {
            fiberAdjustment = 1.0
            fiberDescription = "Moderate fiber (\(String(format: "%.1f", fiber))g) - moderately slows absorption"
        } else {
            fiberAdjustment = 0.0
            fiberDescription = "Low fiber (\(String(format: "%.1f", fiber))g) - minimal impact"
        }

        let mealSizeAdjustment: Double
        let mealSizeDescription: String

        if calories > 800 {
            mealSizeAdjustment = 2.0
            mealSizeDescription = "Large meal (\(String(format: "%.0f", calories)) cal) - delayed gastric emptying"
        } else if calories > 400 {
            mealSizeAdjustment = 1.0
            mealSizeDescription = "Medium meal (\(String(format: "%.0f", calories)) cal) - moderate impact"
        } else {
            mealSizeAdjustment = 0.0
            mealSizeDescription = "Small meal (\(String(format: "%.0f", calories)) cal) - minimal impact"
        }

        let totalHours = min(max(baselineHours + fpuAdjustment + fiberAdjustment + mealSizeAdjustment, 2.0), 8.0)

        let reasoning = "RECALCULATED after food deletion: " +
            "BASELINE: \(String(format: "%.1f", baselineHours)) hours for \(String(format: "%.1f", carbs))g carbs. " +
            "FPU IMPACT: \(fpuDescription) (+\(String(format: "%.1f", fpuAdjustment)) hours). " +
            "FIBER EFFECT: \(fiberDescription) (+\(String(format: "%.1f", fiberAdjustment)) hours). " +
            "MEAL SIZE: \(mealSizeDescription) (+\(String(format: "%.1f", mealSizeAdjustment)) hours). " +
            "TOTAL: \(String(format: "%.1f", totalHours)) hours for remaining meal composition."

        return (totalHours, reasoning)
    }
}
