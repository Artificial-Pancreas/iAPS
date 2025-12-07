import Combine
import SwiftUI

struct FoodSearchView: View {
    @ObservedObject var state: FoodSearchStateModel
    var onSelect: (AIFoodItem, UIImage?) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 8) {
                    ZStack(alignment: .trailing) {
                        TextField("Food Search...", text: $state.foodSearchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.search)
                            .onSubmit {
                                state.searchByText(query: state.foodSearchText)
                            }

                        if state.isBarcode {
                            Text("barcode")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .padding(.trailing, 6)
                        }
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

                    Image(systemName: "camera")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .padding(8)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.purple)
                        .onTapGesture {
                            state.overrideCameraByDefault = false
                            state.navigateToAICamera = true
                        }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            state.overrideCameraByDefault = true
                            state.navigateToAICamera = true
                        }
                }
                .padding(.horizontal)
                .padding(.top, 12)

                SearchResultsView(
                    state: state,
                    onFoodItemSelected: { foodItem in
                        handleFoodItemSelection(foodItem, image: state.aiAnalysisRequest?.image)
                    },
                    onCompleteMealSelected: { totalMeal in
                        handleFoodItemSelection(totalMeal, image: state.aiAnalysisRequest?.image)
                    }
                )
                .padding(.top, 4)
            }

//            .navigationTitle("Food Search")
//            .navigationBarItems(trailing: Button("Done") { dismiss() })
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
                if UserDefaults.standard.alwaysOpenCamera, !state.overrideCameraByDefault {
                    AICameraView(
                        onImageCaptured: { image in
                            state.navigateToAICamera = false
                            state.navigateToAIAnalysis = AnalysisRoute(request: AnalysisRequest.image(image))
                        },
                        onCancel: { state.navigateToAICamera = false },
                        showingImagePicker: true,
                        imageSourceType: .camera
                    )
                } else {
                    AICameraView(
                        onImageCaptured: { image in
                            state.navigateToAICamera = false
                            state.navigateToAIAnalysis = AnalysisRoute(request: AnalysisRequest.image(image))
                        },
                        onCancel: { state.navigateToAICamera = false }
                    )
                }
            }
            .navigationDestination(item: $state.navigateToAIAnalysis) { analysisRoute in
                AIProgressView(
                    analysisRequest: analysisRoute.request,
                    onFoodAnalyzed: { analysisResult, analysisRequest in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            handleAIAnalysis(analysisResult, image: analysisRequest.image)
                            state.aiAnalysisRequest = analysisRequest
                            state.navigateToAICamera = false
                            state.navigateToAIAnalysis = nil
                        }
                    },
                    onCancel: {
                        state.navigateToAICamera = false
                        state.navigateToAIAnalysis = nil
                    }
                )
            }
            .sheet(item: $state.latestTextSearch) { searchResult in
                TextSearchResultsSheet(
                    searchResult: searchResult,
                    onFoodItemSelected: { selectedItem in
                        state.addItem(selectedItem)
                        state.latestTextSearch = nil
                    },
                    onDismiss: {
                        state.latestTextSearch = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }.background(Color(.systemBackground))
    }

    private func handleBarcodeScan(_ barcode: String) {
        print("📦 Barcode scanned: \(barcode)")
        state.navigateToBarcode = false
        state.enterBarcodeAndSearch(barcode: barcode)
        print("🔍 Search for Barcode: \(barcode)")
    }

    private func handleAIAnalysis(_ analysisResult: FoodAnalysisResult, image _: UIImage?) { // ✅ Parameter name korrigiert
        state.searchResults = [analysisResult] + state.searchResults
    }

    private func handleFoodItemSelection(_ foodItem: AIFoodItem, image: UIImage?) {
        onSelect(foodItem, image)
        dismiss()
    }
}
