@testable import FreeAPS
import XCTest

class FileStorageTests: XCTestCase {
    let fileStorage = BaseFileStorage()

    struct DummyObject: JSON {
        let id: String
        let value: Decimal
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Every stored setting must survive a save and a reload: `FreeAPSSettings` decodes key by key (to accept
    /// incomplete files), so a property the decoder misses silently reverts to its default on every app start.
    /// Every encoded value gets a non-default one, a nested object's field by field (`nightTime.startHour`), so a new
    /// property, or a field a nested decoder misses, is covered without listing it here; one whose type rejects the
    /// generic change (an enum, a date) gets its value in `seed` (which sets only that value, not its object's others).
    func testFreeAPSSettingsRoundTripKeepsEveryProperty() throws {
        var seed = FreeAPSSettings()
        seed.units = .mgdL
        seed.displayOnWatch = .steps
        seed.lightMode = .dark
        seed.birthDate = Date(timeIntervalSince1970: 643_000_000)

        let defaults = try leaves(jsonObject(FreeAPSSettings()))
        let expected = try nonDefault(jsonObject(seed), defaults: jsonObject(FreeAPSSettings()))
        let expectedLeaves = leaves(expected)
        for (path, value) in expectedLeaves {
            XCTAssertNotEqual(value as? NSObject, defaults[path] as? NSObject, "\(path): give it a non-default value in seed")
        }

        let decoded = try JSONCoding.decoder.decode(
            FreeAPSSettings.self,
            from: JSONSerialization.data(withJSONObject: expected)
        )
        let actual = try leaves(jsonObject(decoded))

        XCTAssertEqual(Set(actual.keys), Set(expectedLeaves.keys))
        for (path, value) in expectedLeaves {
            XCTAssertEqual(actual[path] as? NSObject, value as? NSObject, "\(path) is not decoded")
        }
        XCTAssertEqual(decoded.ketoProtectBasalPercent, 21)
    }

    private func jsonObject(_ settings: FreeAPSSettings) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(settings)) as? [String: Any])
    }

    /// `seed`'s values, each one equal to its default changed (`nonDefault`); a nested object field by field, whatever
    /// `seed` set in it.
    private func nonDefault(_ seed: [String: Any], defaults: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in seed {
            if let nested = value as? [String: Any] {
                result[key] = nonDefault(nested, defaults: defaults[key] as? [String: Any] ?? [:])
            } else if (value as? NSObject) == (defaults[key] as? NSObject) {
                result[key] = nonDefault(value)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private func nonDefault(_ value: Any) -> Any {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return !number.boolValue
        case let number as NSNumber:
            // A whole number, so Decimal and Double settings round-trip exactly
            return Int(number.doubleValue.rounded(.down)) + 1
        case let string as String:
            return string + " (changed)"
        default:
            return value
        }
    }

    /// Every value of `object` that is not an object, by its path (`nightTime.startHour`).
    private func leaves(_ object: [String: Any], prefix: String = "") -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in object {
            if let nested = value as? [String: Any] {
                result.merge(leaves(nested, prefix: prefix + key + "."), uniquingKeysWith: { first, _ in first })
            } else {
                result[prefix + key] = value
            }
        }
        return result
    }
}
