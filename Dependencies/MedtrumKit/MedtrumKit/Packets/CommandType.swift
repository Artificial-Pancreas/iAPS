enum CommandType {
    static let SYNCHRONIZE: UInt8 = 3
    static let SUBSCRIBE: UInt8 = 4
    static let AUTH_REQ: UInt8 = 5
    static let GET_DEVICE_TYPE: UInt8 = 6
    static let SET_TIME: UInt8 = 10
    static let GET_TIME: UInt8 = 11
    static let SET_TIME_ZONE: UInt8 = 12
    static let PRIME: UInt8 = 16
    static let ACTIVATE: UInt8 = 18
    static let SET_BOLUS: UInt8 = 19
    static let CANCEL_BOLUS: UInt8 = 20
    static let SET_BASAL_PROFILE: UInt8 = 21
    static let SET_TEMP_BASAL: UInt8 = 24
    static let CANCEL_TEMP_BASAL: UInt8 = 25
    static let SUSPEND_PUMP: UInt8 = 28
    static let RESUME_PUMP: UInt8 = 29
    static let POLL_PATCH: UInt8 = 30
    static let STOP_PATCH: UInt8 = 31
    static let READ_BOLUS_STATE: UInt8 = 34
    static let SET_PATCH: UInt8 = 35
    static let SET_BOLUS_MOTOR: UInt8 = 36
    static let GET_RECORD: UInt8 = 99
    static let CLEAR_ALARM: UInt8 = 115
}
