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

    private var foodSearchFullScreenRoute: Binding<FoodSearchFullScreenRoute?> {
        Binding(
            get: { state.foodSearchRoute?.fullScreenRoute },
            set: { state.foodSearchRoute = $0?.route }
        )
    }

    private var foodSearchSheetRoute: Binding<FoodSearchSheetRoute?> {
        Binding(
            get: { state.foodSearchRoute?.sheetRoute },
            set: { state.foodSearchRoute = $0?.route }
        )
    }

    var body: some View {
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
        .fullScreenCover(item: foodSearchFullScreenRoute) { route in
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
        .sheet(item: foodSearchSheetRoute) { route in
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
}
