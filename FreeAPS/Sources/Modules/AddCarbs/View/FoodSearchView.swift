import Combine
import SwiftUI

struct FoodSearchView: View {
    @ObservedObject var state: FoodSearchStateModel
    var onSelect: (FoodItem, UIImage?) -> Void
    @Environment(\.dismiss) var dismiss

    // Navigation States
    @State private var showingAIAnalysisResults = false
    @State private var aiAnalysisResult: AIFoodAnalysisResult?
    @State private var aiAnalysisImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Suchleiste ausgelagert für isoliertes Rendering
                searchBar
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                // HIER WURDE DIE SCROLLVIEW ENTFERNT!
                // Die Ergebnis-Views verwalten ihr Scrolling jetzt selbst.
                if showingAIAnalysisResults, let result = aiAnalysisResult {
                    AIAnalysisResultsView(
                        analysisResult: result,
                        onFoodItemSelected: { foodItem in
                            let selectedFood = FoodItem(
                                name: foodItem.name,
                                carbs: foodItem.carbs,
                                fat: foodItem.fat,
                                protein: foodItem.protein,
                                source: "AI Analysis",
                                imageURL: nil
                            )
                            handleFoodItemSelection(selectedFood, image: aiAnalysisImage)
                        },
                        onCompleteMealSelected: { totalMeal in
                            onSelect(totalMeal, aiAnalysisImage)
                            dismiss()
                        }
                    )
                } else {
                    FoodSearchResultsView(
                        searchResults: state.searchResults,
                        aiSearchResults: state.aiSearchResults,
                        isSearching: state.isLoading,
                        errorMessage: state.errorMessage,
                        onProductSelected: { selectedProduct in
                            let foodItem = selectedProduct.toFoodItem()
                            handleFoodItemSelection(foodItem, image: nil)
                        },
                        onAIProductSelected: { aiProduct in
                            let foodItem = FoodItem(
                                name: aiProduct.name,
                                carbs: Decimal(aiProduct.carbs),
                                fat: Decimal(aiProduct.fat),
                                protein: Decimal(aiProduct.protein),
                                source: "AI Analyse",
                                imageURL: aiProduct.imageURL
                            )
                            handleFoodItemSelection(foodItem, image: nil)
                        }
                    )
                }
            }
            .navigationTitle("Food Search")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .navigationDestination(isPresented: $state.navigateToBarcode) {
                BarcodeScannerView(
                    onBarcodeScanned: { barcode in
                        handleBarcodeScan(barcode)
                        state.navigateToBarcode = false
                    },
                    onCancel: { state.navigateToBarcode = false }
                )
            }
            .navigationDestination(isPresented: $state.navigateToAICamera) {
                AICameraView(
                    onFoodAnalyzed: { analysisResult, image in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            handleAIAnalysis(analysisResult, image: image)
                            state.navigateToAICamera = false
                        }
                    },
                    onCancel: { state.navigateToAICamera = false }
                )
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("Food Search...", text: $state.foodSearchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .onSubmit {
                    state.performSearch(query: state.foodSearchText)
                }

            Button {
                state.navigateToBarcode = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }

            Button {
                state.navigateToAICamera = true
            } label: {
                Image(systemName: "camera")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .padding(8)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.purple)
            }
        }
    }

    // MARK: - Handlers

    private func handleBarcodeScan(_ barcode: String) {
        state.navigateToBarcode = false
        state.foodSearchText = barcode
        state.performSearch(query: barcode)
    }

    private func handleAIAnalysis(_ analysisResult: AIFoodAnalysisResult, image: UIImage?) {
        aiAnalysisResult = analysisResult
        showingAIAnalysisResults = true
        aiAnalysisImage = image

        let aiFoodItems = analysisResult.foodItemsDetailed.map { foodItem in
            AIFoodItem(
                name: foodItem.name,
                brand: nil,
                calories: foodItem.calories ?? 0,
                carbs: foodItem.carbohydrates,
                protein: foodItem.protein ?? analysisResult.totalProtein ?? 0,
                fat: foodItem.fat ?? analysisResult.totalFat ?? 0,
                imageURL: nil
            )
        }
        state.aiSearchResults = aiFoodItems
    }

    private func handleFoodItemSelection(_ foodItem: FoodItem, image: UIImage?) {
        onSelect(foodItem, image)
        dismiss()
    }
}
