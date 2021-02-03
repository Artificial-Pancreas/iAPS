final class BaseAPSManager: APSManager {
    private let openAPS = OpenAPS()

    func runTest() {
        openAPS.test()
    }
}
