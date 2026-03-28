import Combine
import Photos
import SwiftUI

enum FoodSearchRoute {
    case camera
    case barcodeScanner
    case aiProgress
    case imageCommentInput(UIImage)

    var fullScreenRoute: FoodSearchFullScreenRoute? {
        switch self {
        case .camera: .camera
        case .aiProgress: .aiProgress
        case .barcodeScanner: .barcodeScanner
        case .imageCommentInput: nil
        }
    }

    var sheetRoute: FoodSearchSheetRoute? {
        switch self {
        case .camera: nil
        case .aiProgress: nil
        case .barcodeScanner: nil
        case let .imageCommentInput(image): .imageCommentInput(image)
        }
    }
}

enum FoodSearchFullScreenRoute: Identifiable {
    case camera
    case barcodeScanner
    case aiProgress

    var id: FoodSearchFullScreenRoute { self }

    var route: FoodSearchRoute {
        switch self {
        case .camera: .camera
        case .barcodeScanner: .barcodeScanner
        case .aiProgress: .aiProgress
        }
    }
}

enum FoodSearchSheetRoute: Identifiable {
    case imageCommentInput(UIImage)

    var id: String {
        switch self {
        case .imageCommentInput: return "imageCommentInput"
        }
    }

    var route: FoodSearchRoute {
        switch self {
        case let .imageCommentInput(image): .imageCommentInput(image)
        }
    }
}
