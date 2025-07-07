@testable import MedtrumKit
import XCTest

final class CryptoTests: XCTestCase {
    func testKeyGen() throws {
        let input = Data([217, 249, 118, 170]) // 2859923929
        let expected = Data([235, 57, 134, 200]) // 3364239851

        let result = Crypto.genKey(input)
        XCTAssertEqual(result, expected, "Failed to generate correct key based on SN")
    }

    func testKeyDecrypt() throws {
        let input = Data([217, 249, 118, 170]) // 2859923929
        let expected = Data([33, 191, 130, 7]) // 126009121

        let result = Crypto.simpleDecrypt(input)
        XCTAssertEqual(result, expected, "Failed to decrypt key to correct SN")
    }
}
