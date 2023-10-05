import Foundation

struct RawFetchedProfile: JSON, Codable {
    let _id: String
    let defaultProfile: String
    let startDate: String
    let mills: Decimal
    let enteredBy: String
    let store: RawFetchedProfileStore
    let created_at: String

    struct RawFetchedProfileStore: Codable {
        let `default`: ScheduledNightscoutProfile
        struct RawFetchedProfileStoreContent: Codable {
            let dia: Decimal
            let carbs_hr: Int
            let delay: Decimal
            let timezone: String
            let target_low: [NightscoutTimevalue]
            let target_high: [NightscoutTimevalue]
            let sens: [NightscoutTimevalue]
            let basal: [NightscoutTimevalue]
            let carbratio: [NightscoutTimevalue]
            let units: String
        }
    }
}
