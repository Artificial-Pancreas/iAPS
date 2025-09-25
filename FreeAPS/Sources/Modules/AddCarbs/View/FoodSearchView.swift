import Combine
import SwiftUI

struct FoodSearchView: View {
    @ObservedObject var state: FoodSearchStateModel
    var onSelect: (FoodItem) -> Void
    @Environment(\.dismiss) var dismiss

    // Navigation States
    @State private var navigateToBarcode = false
    @State private var navigateToAICamera = false
    @State private var showingAIAnalysisResults = false
    @State private var aiAnalysisResult: AIFoodAnalysisResult?

    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 8) {
                    TextField("Food Search...", text: $state.foodSearchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit {
                            state.performSearch(query: state.foodSearchText)
                        }

                    // Barcode Button
                    Button {
                        navigateToBarcode = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // AI Kamera Button
                    Button {
                        navigateToAICamera = true
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
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    if showingAIAnalysisResults, let result = aiAnalysisResult {
                        AIAnalysisResultsView(
                            analysisResult: result,
                            onFoodItemSelected: { foodItem in
                                onSelect(foodItem)
                                dismiss()
                            },
                            onCompleteMealSelected: { totalMeal in
                                onSelect(totalMeal)
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
                                onSelect(foodItem)
                                dismiss()
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
                                onSelect(foodItem)
                                dismiss()
                            }
                        )
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Food Search")
            .navigationBarItems(trailing: Button("Fertig") { dismiss() })
            .navigationDestination(isPresented: $navigateToBarcode) {
                BarcodeScannerView(
                    onBarcodeScanned: { barcode in
                        handleBarcodeScan(barcode)
                        navigateToBarcode = false
                    },
                    onCancel: { navigateToBarcode = false }
                )
            }
            .navigationDestination(isPresented: $navigateToAICamera) {
                AICameraView(
                    onFoodAnalyzed: { analysisResult, image in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            handleAIAnalysis(analysisResult, image: image)
                            navigateToAICamera = false
                        }
                    },
                    onCancel: { navigateToAICamera = false }
                )
            }
        }
    }

    private func handleBarcodeScan(_ barcode: String) {
        print("📦 Barcode gescannt: \(barcode)")
        navigateToBarcode = false
        state.foodSearchText = barcode
        state.performSearch(query: barcode)
        print("🔍 Suche nach Barcode: \(barcode)")
    }

    private func handleAIAnalysis(_ analysisResult: AIFoodAnalysisResult, image _: UIImage?) {
        aiAnalysisResult = analysisResult
        showingAIAnalysisResults = true

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
}
