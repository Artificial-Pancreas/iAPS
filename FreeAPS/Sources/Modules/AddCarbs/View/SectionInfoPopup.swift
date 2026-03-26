import Foundation
import SwiftUI

struct SectionInfoPopup: View {
    let foodItemGroup: FoodItemGroup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let title = foodItemGroup.briefDescription, !title.isEmpty {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                }

                if let description = foodItemGroup.overallDescription, !description.isEmpty {
                    FoodInfoCard(icon: "text.quote", title: "Description", content: description, color: .gray, embedIcon: true)
                        .padding(.horizontal)
                }

                if let diabetesInfo = foodItemGroup.diabetesConsiderations, !diabetesInfo.isEmpty {
                    FoodInfoCard(
                        icon: "cross.case.fill",
                        title: "Diabetes Recommendations",
                        content: diabetesInfo,
                        color: .blue,
                        embedIcon: true
                    )
                    .padding(.horizontal)
                }

                Spacer(minLength: 8)
            }
            .padding(.vertical)
        }
    }
}
