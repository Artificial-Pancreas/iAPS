import Foundation

public struct NightTimeConfiguration: Codable, Equatable, Sendable {
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var enabled: Bool

    init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, enabled: Bool) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.enabled = enabled
    }
}

final class NightTimeConfigurationTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass {
        NSData.self
    }

    override class func allowsReverseTransformation() -> Bool {
        true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let box = value as? NightTimeConfigurationBox else {
            print("\(#function) cast issue")
            return nil
        }

        do {
            return try NSKeyedArchiver.archivedData(withRootObject: box, requiringSecureCoding: true)
        } catch {
            print("NightTimeConfigurationTransformer encode error:", error)
            return nil
        }
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else {
            print("\(#function) nil data value")
            return nil
        }

        do {
            return try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NightTimeConfigurationBox.self,
                from: data
            )
        } catch {
            print("NightTimeConfigurationTransformer decode error:", error)
            return nil
        }
    }
}

extension NightTimeConfiguration {
    static let `default` = NightTimeConfiguration(
        startHour: 23,
        startMinute: 30,
        endHour: 7,
        endMinute: 0,
        enabled: false
    )
}
