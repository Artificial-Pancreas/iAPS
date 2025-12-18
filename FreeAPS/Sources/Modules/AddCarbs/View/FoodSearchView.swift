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
                        state.foodSearchRoute = .barcodeScanner
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
                            if UserDefaults.standard.alwaysOpenCamera {
                                state.foodSearchRoute = .camera
                            } else {
                                state.foodSearchRoute = .photoSourceSelect
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            state.foodSearchRoute = .photoSourceSelect
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
            .navigationDestination(item: state.navigationRoute) { route in
                switch route {
                case let .aiAnalysis(request, _):
                    AIProgressView(
                        analysisRequest: request,
                        onFoodAnalyzed: { analysisResult, analysisRequest in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                handleAIAnalysis(analysisResult, image: analysisRequest.image)
                                state.aiAnalysisRequest = analysisRequest
                                state.foodSearchRoute = nil
                            }
                        },
                        onCancel: {
                            state.foodSearchRoute = nil
                        }
                    )
                case .photoSourceSelect:
                    AICameraView(
                        onImageCaptured: { image in
                            state.foodSearchRoute = .aiAnalysis(request: AnalysisRequest.image(image))
                        },
                        setRoute: { route in
                            state.foodSearchRoute = route
                        },
                        onCancel: {
                            state.foodSearchRoute = nil
                        },
//                        showingImagePicker: true,
//                        imageSourceType: .camera
                    )
                case .barcodeScanner:
                    BarcodeScannerView(
                        onBarcodeScanned: { barcode in
                            handleBarcodeScan(barcode)
                            state.foodSearchRoute = nil
                        },
                        onCancel: {
                            state.foodSearchRoute = nil
                        }
                    )
                case .camera: // should never happen
                    EmptyView()
                }
            }
            .fullScreenCover(item: state.fullScreenRoute) { route in
                switch route {
                case .camera:
                    ModernCameraView(
                        onImageCaptured: { image in
                            state.foodSearchRoute = .aiAnalysis(request: AnalysisRequest.image(image))
                        }
                    )
                default: // should never happen
                    EmptyView()
                }
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
