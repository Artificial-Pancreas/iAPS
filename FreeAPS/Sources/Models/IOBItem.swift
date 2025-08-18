import Foundation

struct IOBItem: Codable {
    let iob: Decimal
    let activity: Decimal
    let basalIOB: Decimal
    let bolusIOB: Decimal
    let netBasalInsulin: Decimal
    let bolusInsulin: Decimal
    let time: Date
    let iobWithZeroTemp: IOBItemZeroTemp?
    let lastBolusTime: Double?
    let lastTemp: IOBItemLastTemp?

    init(
        iob: Decimal,
        activity: Decimal,
        basalIOB: Decimal,
        bolusIOB: Decimal,
        netBasalInsulin: Decimal,
        bolusInsulin: Decimal,
        time: Date,
        iobWithZeroTemp: IOBItemZeroTemp? = nil,
        lastBolusTime: Double? = nil,
        lastTemp: IOBItemLastTemp? = nil
    ) {
        self.iob = iob
        self.activity = activity
        self.basalIOB = basalIOB
        self.bolusIOB = bolusIOB
        self.netBasalInsulin = netBasalInsulin
        self.bolusInsulin = bolusInsulin
        self.time = time
        self.iobWithZeroTemp = iobWithZeroTemp
        self.lastBolusTime = lastBolusTime
        self.lastTemp = lastTemp
    }
}

extension IOBItem {
    private enum CodingKeys: String, CodingKey {
        case iob
        case activity
        case basalIOB = "basaliob"
        case bolusIOB = "bolusiob"
        case netBasalInsulin = "netbasalinsulin"
        case bolusInsulin = "bolusinsulin"
        case time
        case iobWithZeroTemp
        case lastBolusTime
        case lastTemp
    }
}

struct IOBItemZeroTemp: Codable {
    let iob: Decimal
    let activity: Decimal
    let basalIOB: Decimal
    let bolusIOB: Decimal
    let netBasalInsulin: Decimal
    let bolusInsulin: Decimal
    let time: Date
    let lastBolusTime: Double?
    let lastTemp: IOBItemLastTemp?

    init(
        iob: Decimal,
        activity: Decimal,
        basalIOB: Decimal,
        bolusIOB: Decimal,
        netBasalInsulin: Decimal,
        bolusInsulin: Decimal,
        time: Date,
        lastBolusTime: Double? = nil,
        lastTemp: IOBItemLastTemp? = nil
    ) {
        self.iob = iob
        self.activity = activity
        self.basalIOB = basalIOB
        self.bolusIOB = bolusIOB
        self.netBasalInsulin = netBasalInsulin
        self.bolusInsulin = bolusInsulin
        self.time = time
        self.lastBolusTime = lastBolusTime
        self.lastTemp = lastTemp
    }
}

extension IOBItemZeroTemp {
    private enum CodingKeys: String, CodingKey {
        case iob
        case activity
        case basalIOB = "basaliob"
        case bolusIOB = "bolusiob"
        case netBasalInsulin = "netbasalinsulin"
        case bolusInsulin = "bolusinsulin"
        case time
        case lastBolusTime
        case lastTemp
    }
}

struct IOBItemLastTemp: JSON, Codable, Sendable {
    var date: Decimal
    var duration: Decimal?
    var rate: Decimal?
    var startedAt: Date?
    var timestamp: String?
}

extension IOBItemLastTemp {
    private enum CodingKeys: String, CodingKey {
        case date
        case duration
        case rate
        case startedAt = "started_at"
        case timestamp
    }
}
