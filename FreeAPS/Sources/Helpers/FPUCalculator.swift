import Foundation

func calculateFPU(settings: SettingsManager, protein: Decimal, fat: Decimal) -> [CarbsEntry] {
    let date = Date()
    let interval = settings.settings.minuteInterval // Interval between carbs
    let timeCap = settings.settings.timeCap // Max Duration
    let adjustment = settings.settings.individualAdjustmentFactor
    let delay = settings.settings.delay // Time before first future carb entry

    let kcal = protein * 4 + fat * 9
    let carbEquivalents = (kcal / 10) * adjustment
    let fpus = carbEquivalents / 10

    // Duration in hours used for extended boluses with Warsaw Method. Here used for total duration of the computed carbquivalents instead, excluding the configurable delay.
    var computedDuration = 0
    switch fpus {
    case ..<2:
        computedDuration = 3
    case 2 ..< 3:
        computedDuration = 4
    case 3 ..< 4:
        computedDuration = 5
    default:
        computedDuration = timeCap
    }

    // Size of each created carb equivalent if 60 minutes interval
    var equivalent: Decimal = carbEquivalents / Decimal(computedDuration)
    // Adjust for interval setting other than 60 minutes
    equivalent /= Decimal(60 / interval)
    // Round to 1 fraction digit
    // equivalent = Decimal(round(Double(equivalent * 10) / 10))
    let roundedEquivalent: Double = round(Double(equivalent * 10)) / 10
    equivalent = Decimal(roundedEquivalent)
    // Number of equivalents
    var numberOfEquivalents = carbEquivalents / equivalent
    // Only use delay in first loop
    var firstIndex = true
    // New date for each carb equivalent
    var useDate = date
    // Group and Identify all FPUs together
    let fpuID = UUID().uuidString

    // Create an array of all future carb equivalents.
    var futureCarbArray = [CarbsEntry]()
    while carbEquivalents > 0, numberOfEquivalents > 0 {
        if firstIndex {
            useDate = useDate.addingTimeInterval(delay.minutes.timeInterval)
            firstIndex = false
        } else { useDate = useDate.addingTimeInterval(interval.minutes.timeInterval) }

        let eachCarbEntry = CarbsEntry(
            id: UUID().uuidString, createdAt: useDate, carbs: equivalent, enteredBy: CarbsEntry.manual,
            isFPU: true,
            fpuID: fpuID
        )
        futureCarbArray.append(eachCarbEntry)
        numberOfEquivalents -= 1
    }

    return futureCarbArray
}
