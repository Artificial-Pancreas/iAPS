//
//  GlucoseBackfillMessageTests.swift
//  xDripG5Tests
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import CGMBLEKit

class GlucoseBackfillMessageTests: XCTestCase {

    func testTxMessage() {
        let message = GlucoseBackfillTxMessage(byte1: 5, byte2: 2, identifier: 0, startTime: 5439415, endTime: 5440614) // 20 minutes

        XCTAssertEqual(Data(hexadecimalString: "50050200b7ff5200660453000000000000007138")!, message.data)
    }

    func testRxMessage() {
        let message = GlucoseBackfillRxMessage(data: Data(hexadecimalString: "51000100b7ff52006604530032000000e6cb9805")!)!

        XCTAssertEqual(.ok, TransmitterStatus(rawValue: message.status))
        XCTAssertEqual(1, message.backfillStatus)
        XCTAssertEqual(0, message.identifier)
        XCTAssertEqual(5439415, message.startTime)
        XCTAssertEqual(5440614, message.endTime)
        XCTAssertEqual(50, message.bufferLength)
        XCTAssertEqual(0xcbe6, message.bufferCRC)

        // 0xbc46
        // 0b10111100 01000110
        var buffer = GlucoseBackfillFrameBuffer(identifier: message.identifier)
        buffer.append(Data(hexadecimalString: "0100bc460000b7ff52008b0006eee30053008500")!)
        buffer.append(Data(hexadecimalString: "020006eb0f025300800006ee3a0353007e0006f5")!)
        buffer.append(Data(hexadecimalString: "030066045300790006f8")!)

        XCTAssertEqual(Int(message.bufferLength), buffer.count)
        XCTAssertEqual(message.bufferCRC, buffer.crc16)

        let messages = buffer.glucose
        
        XCTAssertEqual(139, messages[0].glucose)
        XCTAssertEqual(5439415, messages[0].timestamp)
        XCTAssertEqual(.known(.ok), CalibrationState(rawValue: messages[0].state))
        XCTAssertEqual(-18, messages[0].trend)

        XCTAssertEqual(133, messages[1].glucose)
        XCTAssertEqual(5439715, messages[1].timestamp)
        XCTAssertEqual(.known(.ok), CalibrationState(rawValue: messages[1].state))
        XCTAssertEqual(-21, messages[1].trend)

        XCTAssertEqual(128, messages[2].glucose)
        XCTAssertEqual(5440015, messages[2].timestamp)
        XCTAssertEqual(.known(.ok), CalibrationState(rawValue: messages[2].state))
        XCTAssertEqual(-18, messages[2].trend)

        XCTAssertEqual(126, messages[3].glucose)
        XCTAssertEqual(5440314, messages[3].timestamp)
        XCTAssertEqual(.known(.ok), CalibrationState(rawValue: messages[3].state))
        XCTAssertEqual(-11, messages[3].trend)

        XCTAssertEqual(121, messages[4].glucose)
        XCTAssertEqual(5440614, messages[4].timestamp)
        XCTAssertEqual(.known(.ok), CalibrationState(rawValue: messages[4].state))
        XCTAssertEqual(-08, messages[4].trend)

        XCTAssertEqual(message.startTime, messages.first!.timestamp)
        XCTAssertEqual(message.endTime, messages.last!.timestamp)

        XCTAssertTrue(messages.first!.timestamp <= messages.last!.timestamp)
    }

    func testGlucoseBackfill2() {
        let message = GlucoseBackfillTxMessage(byte1: 5, byte2: 2, identifier: 0, startTime: 4648682, endTime: 4650182) // 25 minutes

        XCTAssertEqual(Data(hexadecimalString: "50050200eaee4600c6f446000000000000009f6d")!, message.data, message.data.hexadecimalString)

        let response = GlucoseBackfillRxMessage(data: Data(hexadecimalString: "51000103eaee4600c6f446003a0000004f3ac9e6")!)!

        XCTAssertEqual(.ok, TransmitterStatus(rawValue: response.status))
        XCTAssertEqual(1, response.backfillStatus)
        XCTAssertEqual(3, response.identifier)
        XCTAssertEqual(4648682, response.startTime)
        XCTAssertEqual(4650182, response.endTime)
        XCTAssertEqual(58, response.bufferLength)
        XCTAssertEqual(0x3a4f, response.bufferCRC)

        // 0x6e3c
        // 0b01101110 00111100
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0xc0)
        buffer.append(Data(hexadecimalString: "01c06e3c0000eaee4600920007fd16f046009500")!)
        buffer.append(Data(hexadecimalString: "02c0070042f14600960007026ef2460099000704")!)
        buffer.append(Data(hexadecimalString: "03c09af3460093000700c6f44600900007fc")!)

        XCTAssertEqual(Int(response.bufferLength), buffer.count)
        XCTAssertEqual(response.bufferCRC, buffer.crc16)

        let messages = buffer.glucose

        XCTAssertEqual(response.startTime, messages.first!.timestamp)
        XCTAssertEqual(response.endTime, messages.last!.timestamp)

        XCTAssertTrue(messages.first!.timestamp <= messages.last!.timestamp)

        XCTAssertEqual(6, messages.count)
    }

    func testMalformedBackfill() {
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0)
        buffer.append(Data(hexadecimalString: "0100bc460000b7ff52008b0006eee30053008500")!)
        buffer.append(Data(hexadecimalString: "020006eb0f025300800006ee3a0353007e0006")!)

        XCTAssertEqual(3, buffer.glucose.count)
    }

    func testGlucoseBackfill3() {
        let response = GlucoseBackfillRxMessage(data: Data(hexadecimalString: "510001023d6a0e00c16d0e00280000005b1a9154")!)!

        XCTAssertEqual(.ok, TransmitterStatus(rawValue: response.status))
        XCTAssertEqual(1, response.backfillStatus)
        XCTAssertEqual(2, response.identifier)
        XCTAssertEqual(944701, response.startTime)
        XCTAssertEqual(945601, response.endTime)
        XCTAssertEqual(40, response.bufferLength)
        XCTAssertEqual(0x1A5B, response.bufferCRC)

        // 0x440c
        // 0b01000100 00001100
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0x80)
        buffer.append(Data(hexadecimalString: "0180440c00003d6a0e005c0007fe696b0e005d00")!)
        buffer.append(Data(hexadecimalString: "028007ff956c0e005e000700c16d0e005d000700")!)

        XCTAssertEqual(Int(response.bufferLength), buffer.count)
        XCTAssertEqual(response.bufferCRC, buffer.crc16)

        let messages = buffer.glucose

        XCTAssertEqual(response.startTime, messages.first!.timestamp)
        XCTAssertEqual(response.endTime, messages.last!.timestamp)

        XCTAssertTrue(messages.first!.timestamp <= messages.last!.timestamp)

        XCTAssertEqual(4, messages.count)
    }

    func testGlucoseBackfill4() {
        let response = GlucoseBackfillRxMessage(data: Data(hexadecimalString: "51000103c9740e004d780e0028000000235bd94c")!)!

        XCTAssertEqual(.ok, TransmitterStatus(rawValue: response.status))
        XCTAssertEqual(1, response.backfillStatus)
        XCTAssertEqual(3, response.identifier)
        XCTAssertEqual(947401, response.startTime)
        XCTAssertEqual(948301, response.endTime)
        XCTAssertEqual(40, response.bufferLength)
        XCTAssertEqual(0x5B23, response.bufferCRC)

        // 0x04d0
        // 0b00000100 11010000
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0xc0)
        buffer.append(Data(hexadecimalString: "01c04d0c0000c9740e005a000700f5750e005800")!)
        buffer.append(Data(hexadecimalString: "02c007ff21770e00590007ff4d780e0059000700")!)

        XCTAssertEqual(Int(response.bufferLength), buffer.count)
        XCTAssertEqual(response.bufferCRC, buffer.crc16)

        let messages = buffer.glucose

        XCTAssertEqual(response.startTime, messages.first!.timestamp)
        XCTAssertEqual(response.endTime, messages.last!.timestamp)

        XCTAssertTrue(messages.first!.timestamp <= messages.last!.timestamp)

        XCTAssertEqual(4, messages.count)
    }

    func testNotGlucoseBackfill1() {
        let response = GlucoseBackfillRxMessage(data: Data(hexadecimalString: "5100010339410e0085a90e00ac06000070ca9143")!)!

        XCTAssertEqual(.ok, TransmitterStatus(rawValue: response.status))
        XCTAssertEqual(1, response.backfillStatus)
        XCTAssertEqual(3, response.identifier)
        XCTAssertEqual(934201, response.startTime)
        XCTAssertEqual(960901, response.endTime)
        XCTAssertEqual(1708, response.bufferLength)
        XCTAssertEqual(0xCA70, response.bufferCRC)

        // 0x4a4f
        // 0b01001010 01001111
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0xc0)
        buffer.append(Data(hexadecimalString: "01c04a4f4a5558ef554453b7392a0df008571a7f")!)
        buffer.append(Data(hexadecimalString: "02c0451e0d74bdec596b633cf2b03d511ef3d048")!)
        buffer.append(Data(hexadecimalString: "03c009145e959ca51f7a1663ca31676b175d7bc7")!)
        buffer.append(Data(hexadecimalString: "04c0de00c954fcd3281d5163ed873cdc136fca3e")!)
        buffer.append(Data(hexadecimalString: "05c0c7da188dd5fbb8997206da1cc8d0c22f8434")!)
        buffer.append(Data(hexadecimalString: "06c04d50b29df06b12e7162f2d73fd553e44e469")!)
        buffer.append(Data(hexadecimalString: "07c02b4bb61d66cf6e949ee0f07dbe0cc12127ae")!)
        buffer.append(Data(hexadecimalString: "08c03bf887be09ece7595adfee494b25368103b4")!)
        buffer.append(Data(hexadecimalString: "09c07eefb9b5398468a53f00355341d19b50c8b1")!)
        buffer.append(Data(hexadecimalString: "0ac028f0ddb4dc09a2c74deedf7fdff13fcd6b0e")!)
        buffer.append(Data(hexadecimalString: "0bc0ad2d7311ac9ec1908fb7ee5557c463ea4fea")!)
        buffer.append(Data(hexadecimalString: "0cc0bf3c62d9aa62d7c3d447c959b51d31fd016d")!)
        buffer.append(Data(hexadecimalString: "0dc0278116abd1252ad66c894a39ed7c6d72086e")!)
        buffer.append(Data(hexadecimalString: "0ec0aaee3bf9b05ccb7b23e1c27d777173c4d9fd")!)
        buffer.append(Data(hexadecimalString: "0fc044048720d76a696249737f999f944995e44e")!)
        buffer.append(Data(hexadecimalString: "10c0495e4cb7f22327a920a843de1b4522a68108")!)
        buffer.append(Data(hexadecimalString: "11c058c482389192ed920e322b71900d747a9492")!)
        buffer.append(Data(hexadecimalString: "12c0eac06906ff4863f0e8da07d1ead29fc15bd3")!)
        buffer.append(Data(hexadecimalString: "13c0c0be38548fe9e229c64c9c0f3e9b4c4c1d83")!)
        buffer.append(Data(hexadecimalString: "14c018a936bdde548e4244093e77c87adda0a1cf")!)
        buffer.append(Data(hexadecimalString: "15c0fb97d1d147dd0bc6552faa4d62ab553e1682")!)
        buffer.append(Data(hexadecimalString: "16c0f15f8cb77decb934bfe0c711a026dd4bf36b")!)
        buffer.append(Data(hexadecimalString: "17c0bd268b0eee07ed20a0f3856ea449b1503708")!)
        buffer.append(Data(hexadecimalString: "18c00872ed5a996a13480b81fc82b6ca1e7dd379")!)
        buffer.append(Data(hexadecimalString: "19c06fb4c5bc84e63688b0a77edbab85bfb61b45")!)
        buffer.append(Data(hexadecimalString: "1ac071d29d30edb43db6b8e114bbbcd67f9dd3a9")!)
        buffer.append(Data(hexadecimalString: "1bc0569e17a8a80c015def11ddce1b8f194ff6e2")!)
        buffer.append(Data(hexadecimalString: "1cc0df79ffbc1e077fe249b47550feb5dcd53044")!)
        buffer.append(Data(hexadecimalString: "1dc0b557e2ba03caed61de30221b0330e1cc49b1")!)
        buffer.append(Data(hexadecimalString: "1ec006f05e739d737939baf8b14a8b7a6faae96e")!)
        buffer.append(Data(hexadecimalString: "1fc00b82d430e9e75fb8e7e2affbdd292a41fad2")!)
        buffer.append(Data(hexadecimalString: "20c0fbf8e8f2686aaaf19d2809eecd3bd4f63516")!)
        buffer.append(Data(hexadecimalString: "21c0a7df809e73538e459c1a9cd27a566f636e22")!)
        buffer.append(Data(hexadecimalString: "22c0dbb3c23d7d7847dee77311287e6c6b192eb4")!)
        buffer.append(Data(hexadecimalString: "23c0d30038d70241a80b9e390778a897dd1632cc")!)
        buffer.append(Data(hexadecimalString: "24c0177b23127b464c07a499abeff05f13e40998")!)
        buffer.append(Data(hexadecimalString: "25c0855350c7c4a335e95d2e569996639e8341b4")!)
        buffer.append(Data(hexadecimalString: "26c0d42874475710a50764d4a4166c0e420aff7f")!)
        buffer.append(Data(hexadecimalString: "27c0facb1d61cb8057de64546fc9f24f93603093")!)
        buffer.append(Data(hexadecimalString: "28c080befb84f22c60d398f017dde114d0557b27")!)
        buffer.append(Data(hexadecimalString: "29c07555e92425342c0674b62fa517b13ba0e3b0")!)
        buffer.append(Data(hexadecimalString: "2ac0923624bce36c89fade1f66bd7ae1e8e7d598")!)
        buffer.append(Data(hexadecimalString: "2bc0d345ceea668373d31f95b03a6ee7fff1a3b5")!)
        buffer.append(Data(hexadecimalString: "2cc045e409b8d31dd53ae9d353f35738819fbb79")!)
        buffer.append(Data(hexadecimalString: "2dc0a5d31fd3c3b7b217d3f79b245d3714b0523d")!)
        buffer.append(Data(hexadecimalString: "2ec0eb576e0193584bff8ecada0dc54e4ebde86c")!)
        buffer.append(Data(hexadecimalString: "2fc092b8ef52003f8b76e90d920ca738c998bb70")!)
        buffer.append(Data(hexadecimalString: "30c07cfa0f7a69d14b79f605d254a164fd67c658")!)
        buffer.append(Data(hexadecimalString: "31c049a329162e03f41c12db845b73301f5bbb81")!)
        buffer.append(Data(hexadecimalString: "32c08a21ca0995b5aa413897ea9e2b7c563ced07")!)
        buffer.append(Data(hexadecimalString: "33c05d51a18e19209f1c55054bd2f74677c71070")!)
        buffer.append(Data(hexadecimalString: "34c0299e29ae5576a220b0b767fc4e898aaf2df1")!)
        buffer.append(Data(hexadecimalString: "35c0bbb554546b69c53b4b3a63bd524bfbe728e6")!)
        buffer.append(Data(hexadecimalString: "36c0cd4e8c6e10e72950e66bfa0d23b954a7aede")!)
        buffer.append(Data(hexadecimalString: "37c0ea5df836af737298d44b4b156ced47727920")!)
        buffer.append(Data(hexadecimalString: "38c02303edefc4916cfdba55829426c153d0d30c")!)
        buffer.append(Data(hexadecimalString: "39c0dfee091fea60c2da239c9aabef8eddbe49b5")!)
        buffer.append(Data(hexadecimalString: "3ac02788f23fb030e7606329ed24cbee10bc20eb")!)
        buffer.append(Data(hexadecimalString: "3bc00a601d46c10bab8cdf04513a47550b0e4fe5")!)
        buffer.append(Data(hexadecimalString: "3cc072ea5e514432c81e325464e1ac2d659378d2")!)
        buffer.append(Data(hexadecimalString: "3dc0f050e994caa508fdea7202ed70a4acc6e8ab")!)
        buffer.append(Data(hexadecimalString: "3ec069ab0d13863943415b492569db29b9594dbe")!)
        buffer.append(Data(hexadecimalString: "3fc02c37277a98b88956f0def9ad866f44ca6d9f")!)
        buffer.append(Data(hexadecimalString: "40c0e5bd6aa2dbd835fab2ec238de4a635a3f6cb")!)
        buffer.append(Data(hexadecimalString: "41c0aafa8812d94d5fe722b3ecfb74eb4c12c622")!)
        buffer.append(Data(hexadecimalString: "42c08c5b4bb2f28069fc6f9dcb26bc84c0cc01c7")!)
        buffer.append(Data(hexadecimalString: "43c04ad95cefa1f62a18fa2c5a05bac208685cdb")!)
        buffer.append(Data(hexadecimalString: "44c0ffe910ddc010b30f457578ab24a866b8a94d")!)
        buffer.append(Data(hexadecimalString: "45c01b0bb36e58f401eb15da2e6710721e39c573")!)
        buffer.append(Data(hexadecimalString: "46c06165075618fc9626c53acdd9cb8bcfb0719f")!)
        buffer.append(Data(hexadecimalString: "47c081599f76725e30d4de39cdcc7f7c0c918d68")!)
        buffer.append(Data(hexadecimalString: "48c0563b99dce4913105b793f4d539fe668feef6")!)
        buffer.append(Data(hexadecimalString: "49c04ebaaf9f4dfda6cac4d617cd07098fec39f0")!)
        buffer.append(Data(hexadecimalString: "4ac04c1ae961bc4f3e2cd395396dc8098bbf4bd5")!)
        buffer.append(Data(hexadecimalString: "4bc0d95ed88f296e8d68c35085af86e5ef8d8bf0")!)
        buffer.append(Data(hexadecimalString: "4cc0658ccce111259ce8ac5cbedfc46deda77433")!)
        buffer.append(Data(hexadecimalString: "4dc05fda2f8d2885082db4b1356c5e2a0e830471")!)
        buffer.append(Data(hexadecimalString: "4ec066c7813ff84a9da11fe343e5a95bbfa3082c")!)
        buffer.append(Data(hexadecimalString: "4fc03bcfd6fe6d9657d04f06ed7bc461ebe18d47")!)
        buffer.append(Data(hexadecimalString: "50c035bbe880ba24d7c84f73ae061b33d62a1845")!)
        buffer.append(Data(hexadecimalString: "51c0650f0a6bbc91b2771549cf49a5a4faf8b278")!)
        buffer.append(Data(hexadecimalString: "52c07ac551477e6cd10fe6a3b43d62b02569d110")!)
        buffer.append(Data(hexadecimalString: "53c005f79d6de0ec017e7a0c98961ce6770f885d")!)
        buffer.append(Data(hexadecimalString: "54c0d05fee0b5f5bf9de8c61b58f8634ecbf3347")!)
        buffer.append(Data(hexadecimalString: "55c0e0c7d345fbc40f35aed12e82f8ccb0ed9335")!)
        buffer.append(Data(hexadecimalString: "56c0b1c8b263179e")!)

        XCTAssertEqual(Int(response.bufferLength), buffer.count)
        XCTAssertEqual(response.bufferCRC, buffer.crc16)

        let messages = buffer.glucose

        XCTAssertNotEqual(response.startTime, messages.first!.timestamp)
        XCTAssertNotEqual(response.endTime, messages.last!.timestamp)

        XCTAssertEqual(191, messages.count)
    }

    func testNotGlucoseBackfill2() {
        let response = GlucoseBackfillRxMessage(data: Data(hexadecimalString: "51000102b1aa0e00e5b20e00a000000020a39b7e")!)!

        XCTAssertEqual(.ok, TransmitterStatus(rawValue: response.status))
        XCTAssertEqual(1, response.backfillStatus)
        XCTAssertEqual(2, response.identifier)
        XCTAssertEqual(961201, response.startTime)
        XCTAssertEqual(963301, response.endTime)
        XCTAssertEqual(160, response.bufferLength)
        XCTAssertEqual(0xA320, response.bufferCRC)

        // 0xcde3
        // 0b11001101 11100011
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0x80)
        buffer.append(Data(hexadecimalString: "0180cde3fd48248e37a7bf6c2d9d78d4bfef6d5b")!)
        buffer.append(Data(hexadecimalString: "02809f074c9039b6d3b841f422cf36398338f98c")!)
        buffer.append(Data(hexadecimalString: "038004160a5a1ad37c382f3ca23ea215c644f7b6")!)
        buffer.append(Data(hexadecimalString: "04802ed7376fa7c83c3ecf0b645233f9b3c80238")!)
        buffer.append(Data(hexadecimalString: "05805692724e630a703f01b0a942250f725553d2")!)
        buffer.append(Data(hexadecimalString: "06804ca2727a4051033a550da80905caf77c735d")!)
        buffer.append(Data(hexadecimalString: "07808f937b4b9602c5dd6fa13ae983e00783b28e")!)
        buffer.append(Data(hexadecimalString: "088069846e672c106b339159ead9ee1c08e1a159")!)

        XCTAssertEqual(Int(response.bufferLength), buffer.count)
        XCTAssertEqual(response.bufferCRC, buffer.crc16)

        let messages = buffer.glucose

        XCTAssertNotEqual(response.startTime, messages.first!.timestamp)
        XCTAssertNotEqual(response.endTime, messages.last!.timestamp)
        XCTAssertFalse(messages.first!.timestamp <= messages.last!.timestamp)

        XCTAssertEqual(17, messages.count)
    }

    func testNotGlucoseBackfill3() {
        let response = GlucoseBackfillRxMessage(data: Data(hexadecimalString: "51000102b6a36500010c6600ac0600000147db0a")!)!

        XCTAssertEqual(.ok, TransmitterStatus(rawValue: response.status))
        XCTAssertEqual(1, response.backfillStatus)
        XCTAssertEqual(2, response.identifier)
        XCTAssertEqual(6661046, response.startTime)
        XCTAssertEqual(6687745, response.endTime)
        XCTAssertEqual(1708, response.bufferLength)
        XCTAssertEqual(0x4701, response.bufferCRC)

        var buffer = GlucoseBackfillFrameBuffer(identifier: 0x80)
        buffer.append(Data(hexadecimalString: "0180e1234bdf92845cec52822a8894854582b2b2")!)
        buffer.append(Data(hexadecimalString: "02800f8a38cc876ad33ae0acdc25921132cc6f0d")!)
        buffer.append(Data(hexadecimalString: "038032a6cd9e6d447916dd0b9699e499ae79b8d1")!)
        buffer.append(Data(hexadecimalString: "048045f4b95e0ad80955d3a899d6083bd142f863")!)
        buffer.append(Data(hexadecimalString: "05809cf9c189744ab66f6ca5c2833ef27442fa71")!)
        buffer.append(Data(hexadecimalString: "068053694b279275f0d23eb826681e20e5ebb79d")!)
        buffer.append(Data(hexadecimalString: "078098b921155eb5aed63119d5faec3ef3e53a37")!)
        buffer.append(Data(hexadecimalString: "08807c87277557a0828e8dc81ff76f1a6e197103")!)
        buffer.append(Data(hexadecimalString: "0980b8378b133898ce73f7989d67360123e9fdd8")!)
        buffer.append(Data(hexadecimalString: "0a80383ce19d943a38796b594ff95a2dc93bd6a2")!)
        buffer.append(Data(hexadecimalString: "0b806b548c5997dc67ed4fe07bcf236d59dd7f94")!)
        buffer.append(Data(hexadecimalString: "0c802cb2382f40a06fde5f2dff3f0b8226a11f12")!)
        buffer.append(Data(hexadecimalString: "0d8029800ae513c5b7bc8ea733544b7da84ded17")!)
        buffer.append(Data(hexadecimalString: "0e80a95b6c3d36183e4409f916a6f1f775af338e")!)
        buffer.append(Data(hexadecimalString: "0f80d098732f2abcf4a90628f321a048349142ff")!)
        buffer.append(Data(hexadecimalString: "108077294e9d029bdc0602c76671d88ff4a87596")!)
        buffer.append(Data(hexadecimalString: "1180bac50f8d705f6732c34b935a0b06545d6d8f")!)
        buffer.append(Data(hexadecimalString: "1280cf6b9eb0d2f0059c1a7b5c65acb83eb43836")!)
        buffer.append(Data(hexadecimalString: "13802f408f68fc7e48858daecf64d01f3f61827e")!)
        buffer.append(Data(hexadecimalString: "1480cd5975c1062ed45311a2602c0bbc9c78cf21")!)
        buffer.append(Data(hexadecimalString: "1580b6e27f3350bc7d4eb908313710931cbd4f23")!)
        buffer.append(Data(hexadecimalString: "168061f70e5e27e8b72faecfbb58b6b6ff65cbf0")!)
        buffer.append(Data(hexadecimalString: "178066bdd3a0b1e1ed0af8b2af88dcb1f4b1c3a4")!)
        buffer.append(Data(hexadecimalString: "18801eb9326019bca25b74804d196c04d079e495")!)
        buffer.append(Data(hexadecimalString: "1980a29097393f81aaef79ef421af54ccd3c35ed")!)
        buffer.append(Data(hexadecimalString: "1a80a3039b0372ddd79ef65293e4e99484573ab3")!)
        buffer.append(Data(hexadecimalString: "1b807e755140ea79b1913a7c491e606b7d1e4542")!)
        buffer.append(Data(hexadecimalString: "1c800c968daf03958bd8784e1cf8cea4fa903a80")!)
        buffer.append(Data(hexadecimalString: "1d8044c5c7baebadbf8e6877d725ab84484e6755")!)
        buffer.append(Data(hexadecimalString: "1e8036be160e8a03d2c07552fc513c8869170528")!)
        buffer.append(Data(hexadecimalString: "1f8038483ab634e7707e9ab8c8e3f87dd67f423f")!)
        buffer.append(Data(hexadecimalString: "2080f184e4457558d9b7944f21d6421b717ddfb1")!)
        buffer.append(Data(hexadecimalString: "2180bb4da6197852102a3a04b8acccea3c54f0f9")!)
        buffer.append(Data(hexadecimalString: "2280da93975f3ea1c39d2aff5dbbc4b183b66044")!)
        buffer.append(Data(hexadecimalString: "23804678951cdc83923fe5a88bda66221a48360b")!)
        buffer.append(Data(hexadecimalString: "2480aa9dc3fee16106bd551754d896da72ff772c")!)
        buffer.append(Data(hexadecimalString: "2580b825bb4eba580b57caadda1b90b449a8f2c5")!)
        buffer.append(Data(hexadecimalString: "2680117b62c286b395d2bf016848c65953595f19")!)
        buffer.append(Data(hexadecimalString: "27806d524b2b191bd9582f47fd3956ab851207af")!)
        buffer.append(Data(hexadecimalString: "2880c7df85c2ee5e9b3f5ae68ffba44a86e237e8")!)
        buffer.append(Data(hexadecimalString: "2980947fec3646851a510c8a61c0b3b7d90e410b")!)
        buffer.append(Data(hexadecimalString: "2a8014b04b3ff32e4d9d16f46880533cf4562af4")!)
        buffer.append(Data(hexadecimalString: "2b80c754e48edfa84f2f3b29976ce59cc110747d")!)
        buffer.append(Data(hexadecimalString: "2c8095a3ab4b66254954a51ca5e5c92d07be80fc")!)
        buffer.append(Data(hexadecimalString: "2d80bc4afa73d7f222f1b9e56083171057e32ca3")!)
        buffer.append(Data(hexadecimalString: "2e80c88dbe9a052d7ffd29d2f665bdd66811712f")!)
        buffer.append(Data(hexadecimalString: "2f804d2f9ee36fd6f3f48c30429c1629e39bbe3f")!)
        buffer.append(Data(hexadecimalString: "30808b01f598fc6420d85b3190d15f8d55f43faf")!)
        buffer.append(Data(hexadecimalString: "31801c171908c8ded10e81123f453c571c8f5199")!)
        buffer.append(Data(hexadecimalString: "32806275a5652f2447f63f1ab5d0dac84387d80c")!)
        buffer.append(Data(hexadecimalString: "3380f095361816ab06f0209a6ec3411c8f0c6ce1")!)
        buffer.append(Data(hexadecimalString: "3480a99ac0dae0c87f6a1d4ee4fe4e19671c29ba")!)
        buffer.append(Data(hexadecimalString: "3580811db50e1625a3b88305ea5c34b53e20700e")!)
        buffer.append(Data(hexadecimalString: "36800fbf211b6a454c788aa17b0cf14db76695a9")!)
        buffer.append(Data(hexadecimalString: "3780dfc186d1c189114f182709efc464f48c6b2f")!)
        buffer.append(Data(hexadecimalString: "38805e629e8e6457b1ec149897210cb6336b123f")!)
        buffer.append(Data(hexadecimalString: "398045d4dc9f4c074ec0e926a8d1768ae92b4866")!)
        buffer.append(Data(hexadecimalString: "3a801edf0d5d1c1a86c90c5eeef69e115fdd513a")!)
        buffer.append(Data(hexadecimalString: "3b8084223228b158081b465c74454450ec19a4c1")!)
        buffer.append(Data(hexadecimalString: "3c80fa306d71fc211bd9b9e55aeb16c582d21ec2")!)
        buffer.append(Data(hexadecimalString: "3d8072d8bbec74f1436958db431a92fc66cf5dd2")!)
        buffer.append(Data(hexadecimalString: "3e80888ef69a91f8dbb0ce70b6e5ec9289245878")!)
        buffer.append(Data(hexadecimalString: "3f8069c0d6d14e580be92f87a3255e124b25b451")!)
        buffer.append(Data(hexadecimalString: "4080b3cbae3d50ea52720bf5029243a4a9fea906")!)
        buffer.append(Data(hexadecimalString: "4180384321d07a4b5378aa272c9a7247830624b8")!)
        buffer.append(Data(hexadecimalString: "4280acf0b265dd82b68aeec5114161a34135b30e")!)
        buffer.append(Data(hexadecimalString: "43802d709c604266db64a4b5a5e6f6d8cfd7ece1")!)
        buffer.append(Data(hexadecimalString: "44807b48711b0630cd919dbf9ea7bf81efa1e8f1")!)
        buffer.append(Data(hexadecimalString: "4580c0282b679f9746ece875482d5e9a5ed59cb8")!)
        buffer.append(Data(hexadecimalString: "46808c7b718de4299f081449cce9aa9afadfcea9")!)
        buffer.append(Data(hexadecimalString: "478066cd4c36d6e816413b15955c958da4d8e866")!)
        buffer.append(Data(hexadecimalString: "48809b5170078157c542236bc7a09c96bc559069")!)
        buffer.append(Data(hexadecimalString: "49800be65a0bce639c69cd3d64db0fa22570756f")!)
        buffer.append(Data(hexadecimalString: "4a80e5ebd5381b077a8ac56e952b631256a076cc")!)
        buffer.append(Data(hexadecimalString: "4b80fb32d28e39021d49dc7b7ee65272ca1f28c1")!)
        buffer.append(Data(hexadecimalString: "4c8004486cc3dcad9f39c602d3ed9030e327cec3")!)
        buffer.append(Data(hexadecimalString: "4d809a5800c6d647c5f99e40a15327957745dce1")!)
        buffer.append(Data(hexadecimalString: "4e80d03a0b5368fda78b28d3975500ab160ac693")!)
        buffer.append(Data(hexadecimalString: "4f80dbc5ea65f540933f858a425ecdb378f62990")!)
        buffer.append(Data(hexadecimalString: "50802e7980ce9365ad4e434308fb2a8102dc9f6a")!)
        buffer.append(Data(hexadecimalString: "5180b71311e183ad9feecfd43b68072d5a9ad4af")!)
        buffer.append(Data(hexadecimalString: "5280e721c37d2b57f95cbf5f51025fb22b6ca60c")!)
        buffer.append(Data(hexadecimalString: "53805749eb01f070a5b015dcd0f68f5fea0b40c6")!)
        buffer.append(Data(hexadecimalString: "5480fae4ee747357e4d73265ad9411c565c41865")!)
        buffer.append(Data(hexadecimalString: "5580b75e9c62c7c2aa3ea3f94d219ef7330077d7")!)
        buffer.append(Data(hexadecimalString: "5680f2c59ee6b54a")!)

        XCTAssertEqual(Int(response.bufferLength), buffer.count)
        XCTAssertEqual(response.bufferCRC, buffer.crc16)

        let messages = buffer.glucose

        XCTAssertNotEqual(response.startTime, messages.first!.timestamp)
        XCTAssertNotEqual(response.endTime, messages.last!.timestamp)
        XCTAssertFalse(messages.first!.timestamp <= messages.last!.timestamp)

        XCTAssertEqual(191, messages.count)
    }
}
