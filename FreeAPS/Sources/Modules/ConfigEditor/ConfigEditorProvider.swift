import Foundation

extension ConfigEditor {
    final class Provider: BaseProvider, ConfigEditorProvider {
        @Injected() private var storage: FileStorage!

        func load(file: String) -> RawJSON {
            if let value = try? storage.retrieve(file, as: RawJSON.self) {
                return value
            } else if let value = try? storage.retrieve(file, as: [PumpHistoryEvent].self) {
                return value.rawJSON
            }
            return defaults(for: file)
        }

        func urlFor(file: String) -> URL? {
            storage.urlFor(file: file)
        }

        func save(_ value: RawJSON, as file: String) {
            try? storage.save(value, as: file)
        }
    }
}
