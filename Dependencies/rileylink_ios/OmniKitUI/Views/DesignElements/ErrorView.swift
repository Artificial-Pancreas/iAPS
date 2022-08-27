//
//  ErrorView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 3/12/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct ErrorView: View {
    var error: LocalizedError
    
    var criticality: ErrorCriticality
    
    @Environment(\.guidanceColors) var guidanceColors
    
    public enum ErrorCriticality {
        case critical
        case normal
        
        func symbolColor(using guidanceColors: GuidanceColors) -> Color {
            switch self {
            case .critical:
                return guidanceColors.critical
            case .normal:
                return guidanceColors.warning
            }
        }
    }
    
    init(_ error: LocalizedError, errorClass: ErrorCriticality = .normal) {
        self.error = error
        self.criticality = errorClass
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(self.criticality.symbolColor(using: guidanceColors))
                Text(self.error.errorDescription ?? "")
                    .bold()
                    .accessibility(identifier: "label_error_description")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: FrameworkLocalText("Error", comment: "Accessibility label indicating an error occurred"))
            
            Text(self.error.recoverySuggestion ?? "")
                .foregroundColor(.secondary)
                .font(.footnote)
                .accessibility(identifier: "label_recovery_suggestion")
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorView_Previews: PreviewProvider {
    enum ErrorViewPreviewError: LocalizedError {
        case someError
        
        var localizedDescription: String { "It didn't work" }
        var recoverySuggestion: String { "Maybe try turning it on and off." }
    }
    
    static var previews: some View {
        ErrorView(ErrorViewPreviewError.someError)
    }
}
