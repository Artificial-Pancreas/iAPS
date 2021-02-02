import Foundation

protocol FileManager {
    var temporaryDirectory: URL { get }

    func url(
        for: Foundation.FileManager.SearchPathDirectory,
        in: Foundation.FileManager.SearchPathDomainMask,
        appropriateFor: URL?,
        create: Bool
    ) throws -> URL

    func urls(
        for: Foundation.FileManager.SearchPathDirectory,
        in: Foundation.FileManager.SearchPathDomainMask
    ) -> [URL]

    func enumerator(
        at: URL,
        includingPropertiesForKeys: [URLResourceKey]?,
        options: Foundation.FileManager.DirectoryEnumerationOptions,
        errorHandler: ((URL, Error) -> Bool)?
    ) -> Foundation.FileManager.DirectoryEnumerator?

    func createDirectory(
        at: URL,
        withIntermediateDirectories: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws

    func createFile(
        atPath: String,
        contents: Data?,
        attributes: [FileAttributeKey: Any]?
    ) -> Bool

    func removeItem(at: URL) throws

    func moveItem(at: URL, to: URL) throws

    func fileExists(atPath: String) -> Bool

    func attributesOfItem(atPath: String) throws -> [FileAttributeKey: Any]

    func contents(atPath: String) -> Data?
}

extension Foundation.FileManager: FileManager {}
