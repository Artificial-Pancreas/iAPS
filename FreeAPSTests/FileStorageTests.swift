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
}
