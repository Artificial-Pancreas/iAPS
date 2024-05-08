import Combine
import Foundation

extension ContactTrick {
    final class Provider: BaseProvider, ContactTrickProvider {
        private let processQueue = DispatchQueue(label: "ContactTrickProvider.processQueue")

        var contacts: [ContactTrickEntry] {
            storage.retrieve(OpenAPS.Settings.contactTrick, as: [ContactTrickEntry].self)
                ?? [ContactTrickEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.contactTrick))
                ?? []
        }

        func saveContacts(_ contacts: [ContactTrickEntry]) -> AnyPublisher<[ContactTrickEntry], Error> {
            Future { promise in
                self.contactTrickManager.updateContacts(contacts: contacts) { result in
                    switch result {
                    case let .success(updated):
                        promise(.success(updated))
                    case let .failure(error):
                        promise(.failure(error))
                    }
                }
            }.eraseToAnyPublisher()
        }
    }
}
