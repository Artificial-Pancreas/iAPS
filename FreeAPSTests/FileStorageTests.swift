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

    func testStorage() throws {
        let uniqID = UUID().uuidString
        let object1 = DummyObject(id: uniqID, value: 1.0)
        let object2 = DummyObject(id: UUID().uuidString, value: 1.2)
        let object3 = DummyObject(id: UUID().uuidString, value: 1.4)
        let object4 = DummyObject(id: uniqID, value: 1.0)

        do {
            try fileStorage.save(object1, as: "tests/testStorage1.json")
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            try fileStorage.save([object1, object2], as: "tests/testStorage2.json")
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            let value = try fileStorage.retrieve("tests/testStorage1.json", as: DummyObject.self)
            XCTAssert(value.rawJSON == object1.rawJSON)
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            let values = try fileStorage.retrieve("tests/testStorage2.json", as: [DummyObject].self)
            XCTAssert(values.rawJSON == [object1, object2].rawJSON)
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            try fileStorage.append(object3, to: "tests/testStorage1.json")
            let values = try fileStorage.retrieve("tests/testStorage1.json", as: [DummyObject].self)

            XCTAssert(values.rawJSON == [object1, object3].rawJSON)
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            try fileStorage.append([object2, object4], to: "tests/testStorage1.json")
            let values = try fileStorage.retrieve("tests/testStorage1.json", as: [DummyObject].self)

            XCTAssert(values.rawJSON == [object1, object3, object2, object4].rawJSON)
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            try fileStorage.append([object3, object4], to: "tests/testStorage2.json", uniqBy: \.id)
            let values = try fileStorage.retrieve("tests/testStorage2.json", as: [DummyObject].self)

            XCTAssert(values.rawJSON == [object1, object2, object3].rawJSON)
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            try fileStorage.remove("tests/testStorage1.json")
            try fileStorage.rename("tests/testStorage2.json", to: "tests/testStorage1.json")
            let values = try fileStorage.retrieve("tests/testStorage1.json", as: [DummyObject].self)
            XCTAssert(values.rawJSON == [object1, object2, object3].rawJSON)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}
