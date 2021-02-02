import Foundation

enum FileStorageError: Error {
    case cannotCreateDirectory(url: URL, error: Error)
    case cannotCreateFile(url: URL)
    case cannotLoadDataFromDisk(url: URL, error: Error)
    case cannotConvertData(url: URL)
    case fileNotExist
}
