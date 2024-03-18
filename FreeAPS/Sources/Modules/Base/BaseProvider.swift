import Combine
import Foundation
import Swinject

protocol Provider {
    init(resolver: Resolver)
}

class BaseProvider: Provider, Injectable {
    var lifetime = Lifetime()
    @Injected() var deviceManager: DeviceDataManager!
    @Injected() var storage: FileStorage!
    @Injected() var bluetoothProvider: BluetoothStateManager!
    @Injected() var contactTrickManager: ContactTrickManager!

    required init(resolver: Resolver) {
        injectServices(resolver)
    }
}
