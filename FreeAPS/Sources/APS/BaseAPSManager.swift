import Swinject

final class BaseAPSManager: APSManager, Injectable {
    private var openAPS: OpenAPS!

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: resolver.resolve(FileStorage.self)!)
    }

    func runTest() {
        openAPS.test()
    }
}
