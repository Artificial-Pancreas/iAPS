#!/usr/bin/env xcrun --sdk macosx swift

import Foundation

// MARK: Types

struct InfoPlist {
    private typealias Plist = (dict: [String: Any], format: PropertyListSerialization.PropertyListFormat)

    private var fileURL: URL
    private var plist: Plist

    enum Const: String {
        case version = "CFBundleShortVersionString"
        case build = "CFBundleVersion"
        case settings = "PreferenceSpecifiers"
        case settingsValue = "DefaultValue"
    }

    var version: String? {
        get {
            plist.dict[InfoPlist.Const.version.rawValue] as? String
        }
        set {
            plist.dict[InfoPlist.Const.version.rawValue] = newValue
        }
    }

    var build: String? {
        get {
            plist.dict[InfoPlist.Const.build.rawValue] as? String
        }
        set {
            plist.dict[InfoPlist.Const.build.rawValue] = newValue
        }
    }

    var settingsVersion: String? {
        get {
            (
                plist
                    .dict[InfoPlist.Const.settings.rawValue] as! [[String: Any]]
            )[1][
                InfoPlist.Const.settingsValue
                    .rawValue
            ] as? String
        }
        set {
            var dictCopy = plist.dict
            var specs = dictCopy[InfoPlist.Const.settings.rawValue] as! [[String: Any]]
            specs[1][InfoPlist.Const.settingsValue.rawValue] = newValue ?? ""
            dictCopy[InfoPlist.Const.settings.rawValue] = specs
            plist.dict = dictCopy
        }
    }

    private init(fileURL: URL, plist: Plist) {
        self.fileURL = fileURL
        self.plist = plist
    }

    init?(fromFileAtURL fileURL: URL) {
        guard let plist = InfoPlist.readPlist(fromFileAtURL: fileURL) else { return nil }

        self.init(fileURL: fileURL, plist: plist)
    }

    func save() {
        InfoPlist.writePlist(plist, toFileAtURL: fileURL)
    }

    // MARK: Plist file read/write

    private static func readPlist(fromFileAtURL fileURL: URL) -> Plist? {
        var data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return nil
        }

        var format: PropertyListSerialization.PropertyListFormat = .xml
        let dict: [String: Any]
        do {
            dict = try PropertyListSerialization.propertyList(from: data, format: &format) as! [String: Any]
        } catch {
            print("error: Failed to deserialize plist read from file: \(fileURL.absoluteString)")
            print("Error details: \(error)")
            return nil
        }

        return (dict: dict, format: format)
    }

    private static func writePlist(_ plist: Plist, toFileAtURL fileURL: URL) {
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: plist.dict, format: plist.format, options: 0)
        } catch {
            print("error: Failed to serialize plist!")
            return
        }

        do {
            try data.write(to: fileURL)
        } catch {
            print("error: Failed to write file: \(fileURL.absoluteString)")
            print("Error details: \(error)")
            return
        }
    }
}

enum Branch: CustomStringConvertible {
    private static var releasePrefix = "release"

    case Release(version: String)
    case Other(name: String)

    init(_ string: String) {
        let parts = string.components(separatedBy: "/")
        if parts.count >= 2, parts[0] == Branch.releasePrefix {
            self = .Release(version: parts[1])
        } else {
            self = .Other(name: string)
        }
    }

    var description: String {
        switch self {
        case let .Release(version):
            return "\(Branch.releasePrefix)/\(version)"
        case let .Other(name):
            return name
        }
    }
}

// MARK: Helpers

func execute(command: String, args: [String]) -> String? {
    let process = Process()
    process.launchPath = command
    process.arguments = args

    let pipe = Pipe()
    process.standardOutput = pipe
    process.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()

    return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .newlines)
}

func checkdSYM(buildNumber: String?) {
    // Не правильная версия в dSYM может привести к проблемам в работе с сервисами, которые эти dSYM используют (например: Crashlytics)
    // http://tgoode.com/2014/06/05/sensible-way-increment-bundle-version-cfbundleversion-xcode/#comment-600
    // http://tgoode.com/2014/06/05/sensible-way-increment-bundle-version-cfbundleversion-xcode/#comment-2704
    // http://stackoverflow.com/q/13323728
    // http://stackoverflow.com/a/22460268
    if let dsymFolderPath = ProcessInfo.processInfo.environment["DWARF_DSYM_FOLDER_PATH"], !dsymFolderPath.isEmpty,
       let productName = ProcessInfo.processInfo.environment["PRODUCT_NAME"], !productName.isEmpty
    {
        let dsymPlistURL = URL(fileURLWithPath: "\(dsymFolderPath)/\(productName).app.dSYM/Contents/Info.plist")

        guard var dsymInfoPlist = InfoPlist(fromFileAtURL: dsymPlistURL) else {
            print("Failed to read dsym at url \(dsymPlistURL). This is ok for debug builds.")
            return
        }

        dsymInfoPlist.build = buildNumber
        dsymInfoPlist.save()
    }
}

// MARK: Implementation

guard let currentBranch = execute(command: "/usr/bin/git", args: ["rev-parse", "--abbrev-ref", "HEAD"]).map(Branch.init) else {
    print("error: Can't determine current branch!")
    exit(1)
}

guard let commitsCount = execute(command: "/usr/bin/git", args: ["rev-list", "--count", "HEAD"]), !commitsCount.isEmpty else {
    print("error: Can't determine commits count!")
    exit(1)
}

guard let targetBuildDir = ProcessInfo.processInfo.environment["TARGET_BUILD_DIR"], !targetBuildDir.isEmpty else {
    print("error: TARGET_BUILD_DIR environment variable is empty!")
    exit(1)
}

guard let infoPlistPath = ProcessInfo.processInfo.environment["INFOPLIST_PATH"], !infoPlistPath.isEmpty else {
    print("error: INFOPLIST_PATH environment variable is empty!")
    exit(1)
}

guard let infoPlistFile = ProcessInfo.processInfo.environment["INFOPLIST_FILE"], !infoPlistFile.isEmpty else {
    print("error: INFOPLIST_FILE environment variable is empty!")
    exit(1)
}

guard let currentVersion = ProcessInfo.processInfo.environment["CURRENT_PROJECT_VERSION"] else {
    print("error: Current version can't be determined!")
    exit(1)
}

guard var buildInfoPlist = InfoPlist(fromFileAtURL: URL(fileURLWithPath: "\(targetBuildDir)/\(infoPlistPath)")) else {
    print("error: Build Info Plist cannot be load!")
    exit(1)
}

guard let scrRoot = ProcessInfo.processInfo.environment["SRCROOT"], !targetBuildDir.isEmpty else {
    print("error: SRCROOT environment variable is empty!")
    exit(1)
}

guard var sourceInfoPlist = InfoPlist(fromFileAtURL: URL(fileURLWithPath: "\(scrRoot)/FreeAPS/Resources/Info.plist")) else {
    print("error: Source Info Plist cannot be load!")
    exit(1)
}

switch currentBranch {
case let .Release(version):
    buildInfoPlist.version = version
    buildInfoPlist.build = commitsCount
    sourceInfoPlist.build = commitsCount
default:
    buildInfoPlist.build = "\(commitsCount)"
}

buildInfoPlist.save()
sourceInfoPlist.save()

checkdSYM(buildNumber: buildInfoPlist.build)
