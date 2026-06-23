import CoreData
import Foundation

// a snapshot (DTO) of a CoreData Auto_ISF entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct Auto_ISFSnapshot: Sendable {
    let autocr: Bool
    let autoisf: Bool
    let autoisf_max: Decimal?
    let autoisf_min: Decimal?
    let autoISFhourlyChange: Decimal?
    let b30_duration: Decimal?
    let b30factor: Decimal?
    let b30targetLevel: Decimal?
    let b30upperdelta: Decimal?
    let b30upperLimit: Decimal?
    let bgAccelISFweight: Decimal?
    let bgBrakeISFweight: Decimal?
    let date: Date?
    let enableBGacceleration: Bool
    let higherISFrangeWeight: Decimal?
    let id: String?
    let iobThresholdPercent: Decimal?
    let iTime_Start_Bolus: Decimal?
    let iTime_target: Decimal?
    let ketoProtect: Bool
    let ketoProtectAbsolut: Bool
    let ketoProtectBasalAbsolut: Decimal?
    let ketoProtectBasalPercent: Decimal?
    let lowerISFrangeWeight: Decimal?
    let nightTime: NightTimeConfigurationBoxSnapshot?
    let postMealISFweight: Decimal?
    let smbDeliveryRatioBGrange: Decimal?
    let smbDeliveryRatioMax: Decimal?
    let smbDeliveryRatioMin: Decimal?
    let use_B30: Bool
    let variableKetoProtect: Bool
}

extension Auto_ISFSnapshot {
    static func create(from record: Auto_ISF) -> Auto_ISFSnapshot {
        Auto_ISFSnapshot(
            autocr: record.autocr,
            autoisf: record.autoisf,
            autoisf_max: record.autoisf_max?.decimalValue,
            autoisf_min: record.autoisf_min?.decimalValue,
            autoISFhourlyChange: record.autoISFhourlyChange?.decimalValue,
            b30_duration: record.b30_duration?.decimalValue,
            b30factor: record.b30factor?.decimalValue,
            b30targetLevel: record.b30targetLevel?.decimalValue,
            b30upperdelta: record.b30upperdelta?.decimalValue,
            b30upperLimit: record.b30upperLimit?.decimalValue,
            bgAccelISFweight: record.bgAccelISFweight?.decimalValue,
            bgBrakeISFweight: record.bgBrakeISFweight?.decimalValue,
            date: record.date,
            enableBGacceleration: record.enableBGacceleration,
            higherISFrangeWeight: record.higherISFrangeWeight?.decimalValue,
            id: record.id,
            iobThresholdPercent: record.iobThresholdPercent?.decimalValue,
            iTime_Start_Bolus: record.iTime_Start_Bolus?.decimalValue,
            iTime_target: record.iTime_target?.decimalValue,
            ketoProtect: record.ketoProtect,
            ketoProtectAbsolut: record.ketoProtectAbsolut,
            ketoProtectBasalAbsolut: record.ketoProtectBasalAbsolut?.decimalValue,
            ketoProtectBasalPercent: record.ketoProtectBasalPercent?.decimalValue,
            lowerISFrangeWeight: record.lowerISFrangeWeight?.decimalValue,
            nightTime: record.nightTime.map { NightTimeConfigurationBoxSnapshot.create(from: $0) },
            postMealISFweight: record.postMealISFweight?.decimalValue,
            smbDeliveryRatioBGrange: record.smbDeliveryRatioBGrange?.decimalValue,
            smbDeliveryRatioMax: record.smbDeliveryRatioMax?.decimalValue,
            smbDeliveryRatioMin: record.smbDeliveryRatioMin?.decimalValue,
            use_B30: record.use_B30,
            variableKetoProtect: record.variableKetoProtect,
        )
    }
}

// a snapshot (DTO) of a CoreData NightTimeConfigurationBox entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct NightTimeConfigurationBoxSnapshot: Sendable {
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let enabled: Bool

    var value: NightTimeConfiguration {
        NightTimeConfiguration(
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            enabled: enabled
        )
    }
}

extension NightTimeConfigurationBoxSnapshot {
    static func create(from record: NightTimeConfigurationBox) -> NightTimeConfigurationBoxSnapshot {
        NightTimeConfigurationBoxSnapshot(
            startHour: record.startHour,
            startMinute: record.startMinute,
            endHour: record.endHour,
            endMinute: record.endMinute,
            enabled: record.enabled
        )
    }
}
