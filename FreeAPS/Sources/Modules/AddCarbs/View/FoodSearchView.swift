import Combine
import SwiftUI

struct FoodSearchView: View {
    @ObservedObject var state: FoodSearchStateModel
    var onSelect: (FoodItem, UIImage?) -> Void
    @Environment(\.dismiss) var dismiss

    // Navigation States
    @State private var navigateToBarcode = false
    @State private var navigateToAICamera = false
    @State private var showingAIAnalysisResults = false
    @State private var aiAnalysisResult: AIFoodAnalysisResult?
    @State private var aiAnalysisImage: UIImage?

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
                .padding(.top, 8)
            }

            .navigationTitle("Food Search")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
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
        }.background(Color(.systemBackground))
    }

    private func handleBarcodeScan(_ barcode: String) {
        print("📦 Barcode scanned: \(barcode)")
        navigateToBarcode = false
        state.foodSearchText = barcode
        state.performSearch(query: barcode)
        print("🔍 Search for Barcode: \(barcode)")
    }

    private func handleAIAnalysis(_ analysisResult: AIFoodAnalysisResult, image: UIImage?) { // ✅ Parameter name korrigiert
        aiAnalysisResult = analysisResult
        showingAIAnalysisResults = true
        aiAnalysisImage = image // ✅ Bild speichern

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
