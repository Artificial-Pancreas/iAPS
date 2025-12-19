import Combine
import PhotosUI
import SwiftUI

struct FoodSearchView: View {
    @ObservedObject var state: FoodSearchStateModel
    var onSelect: (AIFoodItem, UIImage?) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCameraMenu = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)

                        ZStack(alignment: .trailing) {
                            TextField("Search foods...", text: $state.foodSearchText)
                                .font(.body)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .submitLabel(.search)
                                .onSubmit {
                                    state.searchByText(query: state.foodSearchText)
                                }

                            if state.isBarcode {
                                Text("barcode")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.12))
                                    .cornerRadius(6)
                                    .padding(.trailing, 4)
                            }
                        }

                        // Clear button
                        if !state.foodSearchText.isEmpty {
                            Button(action: {
                                state.foodSearchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemGray5))
                    )

                    // Barcode Scanner Button
                    Button {
                        state.foodSearchRoute = .barcodeScanner
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 46, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.blue.opacity(0.12))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Camera Button with Context Menu
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.purple)
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.purple.opacity(0.12))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Regular tap - open camera
                            state.foodSearchRoute = .camera
                        }
                        .onLongPressGesture(minimumDuration: 0.3) {
                            // Long press - trigger haptic and show menu
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            showCameraMenu = true
                        }
                        .confirmationDialog("Choose Photo Source", isPresented: $showCameraMenu, titleVisibility: .hidden) {
                            Button("Take Photo") {
                                state.foodSearchRoute = .camera
                            }

                            Button("Choose from Library") {
                                showPhotoPicker = true
                            }

                            Button("Cancel", role: .cancel) {}
                        }
                        .photosPicker(
                            isPresented: $showPhotoPicker,
                            selection: $selectedPhotoItem,
                            matching: .images
                        )
                }
                .padding(.horizontal, 16)
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
            }
            .navigationTitle("Food Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading:
                NavigationLink(destination: AISettingsView()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(PlainButtonStyle())
            )
            .navigationBarItems(trailing: Button("Cancel") { dismiss() })

            .fullScreenCover(item: state.fullScreenRoute) { route in
                switch route {
                case .camera:
                    ModernCameraView(
                        onImageCaptured: { image in
                            state.startImageAnalysis(image: image)
                        }
                    )
                case .barcodeScanner:
                    BarcodeScannerView(
                        onBarcodeScanned: { barcode in
                            handleBarcodeScan(barcode)
                        },
                        onCancel: {
                            state.foodSearchRoute = nil
                        }
                    )
                case .aiProgress:
                    AIProgressView(
                        state: state,
                        onCancel: {
                            print("progress view - cancelled")
                            state.cancelSearchTask()
                        }
                    )
                }
            }
            .navigationDestination(item: state.navigationRoute) { route in
                switch route {
                case .barcodeScanner:
                    BarcodeScannerView(
                        onBarcodeScanned: { barcode in
                            handleBarcodeScan(barcode)
                        },
                        onCancel: {
                            state.foodSearchRoute = nil
                        }
                    )
                case .camera: // should never happen
                    EmptyView()
                case .aiProgress: // should never happen
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
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data)
                    {
                        state.startImageAnalysis(image: image)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private func handleBarcodeScan(_ barcode: String) {
        print("📦 Barcode scanned: \(barcode)")
        state.enterBarcodeAndSearch(barcode: barcode)
        print("🔍 Search for Barcode: \(barcode)")
    }

    private func handleFoodItemSelection(_ foodItem: AIFoodItem, image: UIImage?) {
        onSelect(foodItem, image)
        dismiss()
    }
}
