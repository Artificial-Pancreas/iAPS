extension ConfigEditor {
    final class Provider: BaseProvider, ConfigEditorProvider {
        @Injected() private var storage: FileStorage!

        func load(file: String) -> RawJSON {
            (try? storage.retrieve(file, as: RawJSON.self)) ?? defaults(for: file)
        }

        func save(_ value: RawJSON, as file: String) {
            try? storage.save(value, as: file)
        }
    }
}
