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
        NavigationView {
            VStack {
                // Suchfeld + Buttons
                HStack(spacing: 8) {
                    TextField(
                        NSLocalizedString("Food Search...", comment: "Food search placeholder text"),
                        text: $state.foodSearchText
                    )
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
                        AICameraIcon()
                            .frame(width: 24, height: 24)
                            .padding(8)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    // Zeige entweder normale Suchergebnisse oder AI-Analyse-Ergebnisse an
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
                                    source: NSLocalizedString("AI Analyse", comment: "AI Analysis source label")
                                )
                                onSelect(foodItem)
                                dismiss()
                            }
                        )
                    }
                }
                .padding(.top, 8)
                // Navigation-Ziele
                NavigationLink(
                    destination: BarcodeScannerView(
                        onBarcodeScanned: { barcode in
                            handleBarcodeScan(barcode)
                            navigateToBarcode = false
                        },
                        onCancel: { navigateToBarcode = false }
                    ),
                    isActive: $navigateToBarcode,
                    label: { EmptyView() }
                )

                NavigationLink(
                    destination: AICameraView(
                        onFoodAnalyzed: { analysisResult, image in
                            handleAIAnalysis(analysisResult, image: image)
                            navigateToAICamera = false
                        },
                        onCancel: { navigateToAICamera = false }
                    ),
                    isActive: $navigateToAICamera,
                    label: { EmptyView() }
                )

                // Settings
                NavigationLink(destination: AISettingsView()) {
                    HStack {
                        Image(systemName: "gearshape")
                        Text(NSLocalizedString("AI Settings", comment: "AI Settings navigation link"))
                        Spacer()
                    }
                }
                .foregroundStyle(.primary)
                .overlay(
                    Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .semibold)), alignment: .trailing
                ).padding(.horizontal, 20)

                // Footer
                footerNotice
            }
            .navigationTitle(NSLocalizedString("Food Search", comment: "Food Search navigation title"))
            .navigationBarItems(trailing: Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() })
        }
    }

    private var footerNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.circle")
                Text(NSLocalizedString("Notice", comment: "Notice header"))
            }
            .font(.headline)
            .foregroundColor(.orange)
            Text(
                NSLocalizedString(
                    "The food data loaded via OpenFoodFacts always refer to 100g/100ml. This does not apply to values provided by AI Food Analysis.",
                    comment: "Footer notice about food data units"
                )
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(20)
    }

    private func handleBarcodeScan(_ barcode: String) {
        print("📦 Barcode gescannt: \(barcode)")
        navigateToBarcode = false
        state.foodSearchText = barcode
        state.performSearch(query: barcode)
        print("🔍 Suche nach Barcode: \(barcode)")
    }

    private func handleAIAnalysis(_ analysisResult: AIFoodAnalysisResult, image _: UIImage?) {
        // Speichere das vollständige Analyse-Ergebnis
        aiAnalysisResult = analysisResult
        showingAIAnalysisResults = true

        // Füge auch die einfachen Ergebnisse zum State hinzu (für Rückwärtskompatibilität)
        let aiFoodItems = analysisResult.foodItemsDetailed.map { foodItem in
            AIFoodItem(
                name: foodItem.name,
                brand: nil,
                calories: foodItem.calories ?? 0,
                carbs: foodItem.carbohydrates,
                protein: foodItem.protein ?? analysisResult.totalProtein ?? 0,
                fat: foodItem.fat ?? analysisResult.totalFat ?? 0
            )
        }
        state.aiSearchResults = aiFoodItems
    }
}
