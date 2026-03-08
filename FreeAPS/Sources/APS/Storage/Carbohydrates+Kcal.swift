
import Foundation

extension Carbohydrates {
    var carbsInGrams: Double {
        carbs?.doubleValue ?? 0
    }

    var fatInGrams: Double {
        fat?.doubleValue ?? 0
    }

    var proteinInGrams: Double {
        protein?.doubleValue ?? 0
    }

    var kcalDouble: Double {
        kcal?.doubleValue
            ?? (
                carbsInGrams * 4.0
                    + fatInGrams * 9.0
                    + proteinInGrams * 4.0
            )
    }
}
