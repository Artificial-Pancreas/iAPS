import Combine
import PhotosUI
import SwiftUI

struct FoodSearchView: View {
    @ObservedObject var state: FoodSearchStateModel
    let onContinue: (FoodItemDetailed, UIImage?, Date?) -> Void
    let onHypoTreatment: ((FoodItemDetailed, UIImage?, Date?) -> Void)?
    let onPersist: (FoodItemDetailed) -> Void
    let onDelete: (FoodItemDetailed) -> Void
    let continueButtonLabelKey: LocalizedStringKey
    let hypoTreatmentButtonLabelKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: 0) {
            SearchResultsView(
                state: state,
                onContinue: { totalMeal, selectedTime in
                    onContinue(totalMeal, state.aiAnalysisRequest?.image, selectedTime)
                },
                onHypoTreatment: onHypoTreatment != nil ? { totalMeal, selectedTime in
                    onHypoTreatment?(totalMeal, state.aiAnalysisRequest?.image, selectedTime)
                } : nil,
                onPersist: onPersist,
                onDelete: onDelete,
                continueButtonLabelKey: continueButtonLabelKey,
                hypoTreatmentButtonLabelKey: hypoTreatmentButtonLabelKey
            )
        }
        .fullScreenCover(item: state.foodSearchFullScreenRouteBinding) { route in
            switch route {
            case .camera:
                ModernCameraView(
                    onImageCaptured: { image in
                        state.handleImageCaptured(image: image, fromCamera: true)
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
        .sheet(item: state.foodSearchSheetRouteBinding) { route in
            switch route {
            case let .imageCommentInput(image):
                ImageCommentInputView(
                    image: image,
                    onContinue: { comment in
                        state.startImageAnalysis(image: image, comment: comment)
                    },
                    onCancel: {
                        state.foodSearchRoute = nil
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
                    // AI/Search Toggle Button (only when not showing saved foods)
                    if !state.showSavedFoods {
                        Button {
                            state.aiTextAnalysis.toggle()
                        } label: {
                            Image(
                                systemName: state.isBarcode ? FoodItemSource.barcode
                                    .icon : (state.aiTextAnalysis ? FoodItemSource.aiText.icon : FoodItemSource.search.icon)
                            )
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(state.isBarcode ? .blue.opacity(0.5) : (state.aiTextAnalysis ? .purple : .blue))
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        (state.isBarcode ? Color.blue : (state.aiTextAnalysis ? Color.purple : Color.blue))
                                            .opacity(0.12)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(state.isBarcode)
                    }

                    // Search TextField Container
                    HStack(spacing: 10) {
                        // Icon only shown for saved foods
                        if state.showSavedFoods {
                            Image(systemName: FoodItemSource.database.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        DismissableTextField(
                            state
                                .showSavedFoods ? "Search saved foods..." :
                                (state.aiTextAnalysis ? "Ask AI..." : "Search foods..."),
                            text: $state.foodSearchText,
                            textFieldDidBeginEditing: {
                                state.showingFoodSearch = true
                            },
                            returnKeyType: .search,
                            liveEditing: true,
                            onSubmit: {
                                state.searchByText(query: state.foodSearchText)
                                state.showingFoodSearch = true
                            }
                        )

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
                }

                if !state.showSavedFoods, state.latestMultipleSelectSearch == nil {
                    HStack(spacing: 10) {
                        if state.showingFoodSearch {
                            backButton
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            Button {
                                UIApplication.shared.endEditing()
                                state.showingSettings = true
                            }
                            label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .frame(width: 46, height: 46)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button {
                                UIApplication.shared.endEditing()
                                state.showManualEntry = true
                                state.showingFoodSearch = true
                            } label: {
                                Image(systemName: FoodItemSource.manual.icon)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.green)
                                    .frame(width: 46, height: 46)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.green.opacity(0.12))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    UIApplication.shared.endEditing()
                                    state.showSavedFoods = true
                                    state.showingFoodSearch = true
                                }
                            } label: {
                                Image(systemName: FoodItemSource.database.icon)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.orange)
                                    .frame(width: 46, height: 46)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.orange.opacity(0.12))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button {
                                UIApplication.shared.endEditing()
                                state.showingFoodSearch = true
                                state.foodSearchRoute = .barcodeScanner
                            } label: {
                                Image(systemName: FoodItemSource.barcode.icon)
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
                                    UIApplication.shared.endEditing()
                                    state.foodSearchRoute = .camera
                                    state.showingFoodSearch = true
                                }
                                .contextMenu {
                                    Button {
                                        UIApplication.shared.endEditing()
                                        state.foodSearchRoute = .camera
                                        state.showingFoodSearch = true
                                    } label: {
                                        Label("Take Photo", systemImage: "camera")
                                    }

                                    Button {
                                        UIApplication.shared.endEditing()
                                        showPhotoPicker = true
                                        state.showingFoodSearch = true
                                    } label: {
                                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                                    }

                                    Divider()

                                    Button {
                                        UIApplication.shared.endEditing()
                                        state.forceShowCommentForNextImage = true
                                        state.foodSearchRoute = .camera
                                        state.showingFoodSearch = true
                                    } label: {
                                        Label("Photo (+ comment)", systemImage: "camera.badge.ellipsis")
                                    }

                                    Button {
                                        UIApplication.shared.endEditing()
                                        state.forceShowCommentForNextImage = true
                                        showPhotoPicker = true
                                        state.showingFoodSearch = true
                                    } label: {
                                        Label("Library (+ comment)", systemImage: "square.and.pencil")
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
                        state.handleImageCaptured(image: image, fromCamera: false)
                        self.selectedPhotoItem = nil
                    }
                }
            }
        }

        private var backButton: some View {
            Button(action: { state.showingFoodSearch = false }) {
                HStack {
                    Image(systemName: "chevron.left")
                        .resizable()
                        .frame(width: 12, height: 20)
                }
            }
        }
    }
}
