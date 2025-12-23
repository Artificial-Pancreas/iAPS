import Combine
import PhotosUI
import SwiftUI

struct FoodSearchView: View {
    @ObservedObject var state: FoodSearchStateModel
    var onSelect: ([FoodItemDetailed], UIImage?, Date?) -> Void
//    let addButtonLabelKey: LocalizedStringKey
    let addAllButtonLabelKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: 0) {
            SearchResultsView(
                state: state,
                onFoodItemSelected: { foodItem, selectedTime in
                    onSelect([foodItem], state.aiAnalysisRequest?.image, selectedTime)
                },
                onCompleteMealSelected: { totalMeal, selectedTime in
                    onSelect(totalMeal, state.aiAnalysisRequest?.image, selectedTime)
                },
//                addButtonLabelKey: addButtonLabelKey,
                addAllButtonLabelKey: addAllButtonLabelKey
            )
        }
        .fullScreenCover(item: state.foodSearchRouteBinding) { route in
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
                        state.enterBarcodeAndSearch(barcode: barcode)
                    },
                    onCancel: {
                        state.foodSearchRoute = nil
                    }
                )
            case .aiProgress:
                AIProgressView(
                    state: state,
                    onCancel: {
                        state.cancelSearchTask()
                    }
                )
            }
        }
    }

    struct SearchBar: View {
        @ObservedObject var state: FoodSearchStateModel
        @State private var showPhotoPicker = false
        @State private var selectedPhotoItem: PhotosPickerItem?
        @FocusState private var isTextFieldFocused: Bool

        var body: some View {
            VStack(spacing: 10) {
                // First Row - Search Text Field
                HStack(spacing: 10) {
                    Image(
                        systemName: state.showSavedFoods ? "archivebox.fill" : (
                            state.isBarcode ? "barcode" :
                                UserDefaults.standard.textSearchProvider.isAI ? "text.bubble" : "magnifyingglass"
                        )
                    )
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                    ZStack(alignment: .trailing) {
                        TextField(
                            state
                                .showSavedFoods ? "Search saved foods..." :
                                (UserDefaults.standard.textSearchProvider.isAI ? "Ask AI..." : "Search foods..."),
                            text: $state.foodSearchText
                        )
                        .font(.body)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            state.searchByText(query: state.foodSearchText)
                            state.showingFoodSearch = true
                        }
                        .onChange(of: isTextFieldFocused) { _, newValue in
                            if newValue {
                                state.showingFoodSearch = true
                            }
                        }
                        .onChange(of: state.foodSearchText) { _, newValue in
                            // Update the saved foods filter text
                            state.filterText = newValue
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button {
                                    isTextFieldFocused = false
                                } label: {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.blue)
                                }
                            }
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

                if !state.showSavedFoods, !state.showManualEntry, state.latestTextSearch == nil {
                    HStack(spacing: 10) {
                        if state.showingFoodSearch {
                            Button {
                                state.showingFoodSearch = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("Back")
                                        .font(.system(size: 15, weight: .regular))
                                }
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            if state.showingFoodSearch {
                                Button {
                                    state.showManualEntry = true
                                    state.showingFoodSearch = true
                                } label: {
                                    Image(systemName: "text.badge.plus")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.green)
                                        .frame(width: 46, height: 46)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.green.opacity(0.12))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            if state.savedFoods?.foodItemsDetailed.count ?? 0 > 0 {
                                Button {
                                    state.showSavedFoods = true
                                    state.showingFoodSearch = true
                                } label: {
                                    Image(systemName: "archivebox.fill")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.orange)
                                        .frame(width: 46, height: 46)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.orange.opacity(0.12))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            Button {
                                state.showingFoodSearch = true
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
                                    state.foodSearchRoute = .camera
                                    state.showingFoodSearch = true
                                }
                                .contextMenu {
                                    Button {
                                        state.foodSearchRoute = .camera
                                        state.showingFoodSearch = true
                                    } label: {
                                        Label("Take Photo", systemImage: "camera")
                                    }

                                    Button {
                                        showPhotoPicker = true
                                        state.showingFoodSearch = true
                                    } label: {
                                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                                    }
                                }
                                .photosPicker(
                                    isPresented: $showPhotoPicker,
                                    selection: $selectedPhotoItem,
                                    matching: .images
                                )
                        }
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let selectedPhotoItem = newItem else { return }
                Task {
                    if let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data)
                    {
                        state.startImageAnalysis(image: image)
                        self.selectedPhotoItem = nil
                    }
                }
            }
        }
    }
}
