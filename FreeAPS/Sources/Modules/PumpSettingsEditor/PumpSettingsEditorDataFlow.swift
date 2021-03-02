import Combine

enum PumpSettingsEditor {
    enum Config {}
}

protocol PumpSettingsEditorProvider: Provider {
    func settings() -> PumpSettings
    func save(settings: PumpSettings) -> AnyPublisher<Void, Error>
}
