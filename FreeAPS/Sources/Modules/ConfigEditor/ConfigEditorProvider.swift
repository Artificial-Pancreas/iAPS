import Foundation

extension ConfigEditor {
    final class Provider: BaseProvider, ConfigEditorProvider {
        func load(file: String) -> RawJSON {
            storage.retrieveRaw(file) ?? OpenAPS.defaults(for: file)
        }

        func urlFor(file: String) -> URL? {
            storage.urlFor(file: file)
        }

        func save(_ value: RawJSON, as file: String) {
            storage.save(value, as: file)
        }
    }
}
