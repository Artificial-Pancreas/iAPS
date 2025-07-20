import Foundation

enum InsulinCalculations {
    // function to calculate the maximum insulin activity for a given bolus size
    // used to scale the activity chart
    static func peakInsulinActivity(
        forBolus: Double,
        peak: Double,
        dia: Double
    ) -> Double {
        let end = dia * 60.0

        // Calculate tau
        let peakOverEnd = peak / end
        let tauNumerator = peak * (1.0 - peakOverEnd)
        let tauDenominator = 1.0 - 2.0 * peakOverEnd
        guard tauDenominator != 0 else {
            return 0.1
        }
        let tau = tauNumerator / tauDenominator

        // Calculate a
        let a = 2.0 * tau / end

        // Calculate S
        let expNegEndOverTau = exp(-end / tau)
        let S = 1.0 / (1.0 - a + (1.0 + a) * expNegEndOverTau)

        // Calculate activity at peak time
        let t = peak
        let activity = forBolus * (S / pow(tau, 2)) * t * (1.0 - t / end) * exp(-t / tau)

        return activity
    }
    

    // Inverse function to calculate the bolus size needed for a desired peak activity
    // TODO: not tested
    static func bolusForPeakActivity(
        desiredActivity: Double,
        peak: Double,
        dia: Double
    ) -> Double {
        let end = dia * 60.0

        // Calculate tau (same as original function)
        let peakOverEnd = peak / end
        let tauNumerator = peak * (1.0 - peakOverEnd)
        let tauDenominator = 1.0 - 2.0 * peakOverEnd
        guard tauDenominator != 0 else {
            return 0.0
        }
        let tau = tauNumerator / tauDenominator

        // Calculate a (same as original function)
        let a = 2.0 * tau / end

        // Calculate S (same as original function)
        let expNegEndOverTau = exp(-end / tau)
        let S = 1.0 / (1.0 - a + (1.0 + a) * expNegEndOverTau)

        // Calculate the scaling factor at peak time
        let t = peak
        let scalingFactor = (S / pow(tau, 2)) * t * (1.0 - t / end) * exp(-t / tau)

        // Guard against division by zero
        guard scalingFactor != 0 else {
            return 0.0
        }

        // Since activity = forBolus * scalingFactor, then forBolus = activity / scalingFactor
        return desiredActivity / scalingFactor
    }

    
}
