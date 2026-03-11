import Foundation
import SwiftUI

struct TimePickerSheet: View {
    @Binding var selectedTime: Date?
    @Binding var isPresented: Bool
    @State private var pickerDate = Date()

    private var adjustedMealTime: Date {
        let now = Date()
        let calendar = Calendar.current

        let timeComponents = calendar.dateComponents([.hour, .minute], from: pickerDate)

        guard let todayWithSelectedTime = calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: now
        ) else {
            return pickerDate
        }

        let timeDifference = todayWithSelectedTime.timeIntervalSince(now)
        let twelveHoursInSeconds: TimeInterval = 12 * 60 * 60

        if timeDifference > twelveHoursInSeconds {
            return calendar.date(byAdding: .day, value: -1, to: todayWithSelectedTime) ?? todayWithSelectedTime
        } else if timeDifference < -twelveHoursInSeconds {
            return calendar.date(byAdding: .day, value: 1, to: todayWithSelectedTime) ?? todayWithSelectedTime
        } else {
            return todayWithSelectedTime
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker(
                    "Select Time",
                    selection: $pickerDate,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal)

                HStack(spacing: 12) {
                    if selectedTime != nil {
                        Button(action: {
                            selectedTime = nil
                            isPresented = false
                        }) {
                            Text("Use Now")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                    }

                    Button(action: {
                        selectedTime = adjustedMealTime
                        isPresented = false
                    }) {
                        Text("Set Time")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Meal Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            pickerDate = selectedTime ?? Date()
        }
    }
}
