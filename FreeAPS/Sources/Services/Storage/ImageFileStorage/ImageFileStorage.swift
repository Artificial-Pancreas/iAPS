import Combine
import CoreImage
import Swinject

protocol ImageFileStorage: AnyObject {
    var name: String { get }

    func saveImage(_: CIImage, imageClass: String) -> AnyPublisher<URL, FileStorageError>

    func imageClasses() -> [String]
    func fileURLs(imageClass: String) -> [URL]

    func moveImage(url: URL, toImageClass: String) -> AnyPublisher<Void, FileStorageError>

    func remove(url: URL)
}

final class BaseImageFileStorage: ImageFileStorage, Injectable {
    let name: String

    @Injected() private var fileManager: FileManager!

    private let processQueue = DispatchQueue(label: "BaseImageFileStorage.processQueue")
    private var lifetime = Set<AnyCancellable>()

    private lazy var directoryURL: URL = {
        let url = try! fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return url.appendingPathComponent(name, isDirectory: true)
    }()

    init(
        resolver: Resolver,
        name: String
    ) {
        self.name = name
        injectServices(resolver)
    }

    func saveImage(_ image: CIImage, imageClass: String) -> AnyPublisher<URL, FileStorageError> {
        Future<URL, FileStorageError> { promise in
            self.createDirectoryIfNeeded(imageClass: imageClass)
                .receive(on: self.processQueue)
                .sink(receiveCompletion: { res in
                    switch res {
                    case .finished: break
                    case let .failure(error):
                        promise(.failure(error))
                    }
                }, receiveValue: { url in
                    let id = UUID().uuidString
                    let fileURL = url.appendingPathComponent(id).appendingPathExtension("jpeg")

                    let imageData = CIContext().jpegRepresentation(
                        of: image,
                        colorSpace: CGColorSpaceCreateDeviceRGB()
                    )!
                    if self.fileManager.createFile(atPath: fileURL.path, contents: imageData, attributes: nil) {
                        promise(.success(fileURL))
                    } else {
                        promise(.failure(.cannotCreateFile(url: fileURL)))
                    }

                })
                .store(in: &self.lifetime)
        }.eraseToAnyPublisher()
    }

    func imageClasses() -> [String] {
        var urls = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants, .skipsHiddenFiles],
            errorHandler: nil
        )?.allObjects as? [URL] ?? []

        urls = urls.filter { $0.hasDirectoryPath }

        let classes = urls.map(\.lastPathComponent)

        return classes
    }

    func fileURLs(imageClass: String) -> [URL] {
        var urls = fileManager.enumerator(
            at: directory(imageClass: imageClass),
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants, .skipsHiddenFiles],
            errorHandler: nil
        )?.allObjects as? [URL] ?? []

        urls = urls.filter { $0.pathExtension == "jpeg" }

        return urls
    }

    func moveImage(url: URL, toImageClass imageClass: String) -> AnyPublisher<Void, FileStorageError> {
        createDirectoryIfNeeded(imageClass: imageClass)
            .map { (folderURL: URL) -> Void in
                let toURL = folderURL.appendingPathComponent(url.lastPathComponent)
                try? self.fileManager.moveItem(at: url, to: toURL)
            }.eraseToAnyPublisher()
    }

    func remove(url: URL) {
        processQueue.async {
            try? self.fileManager.removeItem(at: url)
        }
    }

    private func directory(imageClass: String) -> URL {
        directoryURL.appendingPathComponent(imageClass)
    }

    private func createDirectoryIfNeeded(imageClass: String) -> AnyPublisher<URL, FileStorageError> {
        Future<URL, FileStorageError> { promise in
            self.processQueue.async {
                let dirURL = self.directory(imageClass: imageClass)
                guard !self.fileManager.fileExists(atPath: dirURL.path) else {
                    promise(.success(dirURL))
                    return
                }
                do {
                    try self.fileManager.createDirectory(
                        at: dirURL,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    promise(.success(dirURL))
                } catch {
                    promise(.failure(.cannotCreateDirectory(url: dirURL, error: error)))
                }
            }
        }.eraseToAnyPublisher()
    }
}
