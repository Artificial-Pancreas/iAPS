import SwiftUI
import Swinject

extension ConfigEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var storage: FileStorage!

        let file: String
        @Published var configText = ""
        @Published var urlForFile: URL?

        init(resolver: Resolver, file: String) {
            self.file = file
            super.init(resolver: resolver)
        }

        override func subscribe() async {
            configText = await load(file: file)
            urlForFile = await storage.urlFor(file: file)
        }

        func save() {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            Task {
                // TODO: display an error in the UI in case of invalid JSON?
                await persist(configText, as: file)
            }
        }

        private func load(file: String) async -> RawJSON {
            await storage.retrieveRaw(file) ?? OpenAPS.defaults(for: file)
        }

        private func persist(_ value: RawJSON, as file: String) async {
            if file.hasSuffix(".js") {
                await storage.save(value, as: file)
                return
            }

            guard let data = value.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else {
                warning(.service, "Invalid JSON")
                return
            }
            await storage.save(value, as: file)
        }
    }
}
