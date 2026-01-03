import Foundation
import SwiftUI

struct TimePickerSheet: View {
    @Binding var selectedTime: Date?
    @Binding var isPresented: Bool
    @State private var pickerDate = Date()

    // Computed property that adjusts the date to ensure the time is within ±12 hours of now
    private var adjustedMealTime: Date {
        let now = Date()
        let calendar = Calendar.current

        // Get the time components from the picker
        let timeComponents = calendar.dateComponents([.hour, .minute], from: pickerDate)

        // Create a date with today's date and the selected time
        guard let todayWithSelectedTime = calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: now
        ) else {
            return pickerDate
        }

        // Calculate the time difference in seconds
        let timeDifference = todayWithSelectedTime.timeIntervalSince(now)
        let twelveHoursInSeconds: TimeInterval = 12 * 60 * 60

        // If the selected time is more than 12 hours in the future, it was probably meant for yesterday
        if timeDifference > twelveHoursInSeconds {
            return calendar.date(byAdding: .day, value: -1, to: todayWithSelectedTime) ?? todayWithSelectedTime
        }
        // If the selected time is more than 12 hours in the past, it was probably meant for tomorrow
        else if timeDifference < -twelveHoursInSeconds {
            return calendar.date(byAdding: .day, value: 1, to: todayWithSelectedTime) ?? todayWithSelectedTime
        }
        // Otherwise, use today with the selected time
        else {
            return todayWithSelectedTime
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Time picker (wheel style for time only)
                DatePicker(
                    "Select Time",
                    selection: $pickerDate,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal)

                // Action buttons
                HStack(spacing: 12) {
                    // Reset to "now" button
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

                    // Set time button
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
            // Initialize picker with current selected time or now
            pickerDate = selectedTime ?? Date()
        }
    }
}
