import SwiftData
import SwiftUI

struct MealsCardContainerView: View {
    @Binding var todayData: MealData
    @State private var showMealsHistory = false
    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            showMealsHistory = true
        } label: {
            MealsSummaryView(data: $todayData)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMealsHistory) {
            MealsHistorySheet()
                .environment(\.modelContext, context)
        }
    }
}
