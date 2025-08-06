import Foundation
import UIKit
// import AudioToolbox

struct SystemSoundInfo {
    let url: URL
    let name: String
    let size: Int
}

class SystemSoundsManager {
    var infos: [SystemSoundInfo] = []

    init() {
        infos = gatherSystemSounds()
    }

    private func gatherSystemSounds() -> [SystemSoundInfo] {
        let fm = FileManager.default
        let baseUrl = URL(fileURLWithPath: "/System/Library/Audio/UISounds")
        let enu = fm.enumerator(
            at: baseUrl,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        )!

        while let fileUrl = enu.nextObject() as? URL {
            do {
                let rv = try fileUrl.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if !rv.isDirectory! {
                    let name = String(fileUrl.path.dropFirst(31))

                    let size = rv.fileSize ?? 0
                    infos.append(SystemSoundInfo(url: fileUrl, name: name, size: size))
                }
            } catch {
                print("🔴 Error: \(error.localizedDescription)")
            }
        }

        return infos.sorted { $0.name < $1.name }
    }

    /// Used to create the list of system sounds in README.md
    private func printAll() {
        print("| Name | Size |")
        print("| --- | --- |")

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = ByteCountFormatter.Units.useKB
        formatter.countStyle = ByteCountFormatter.CountStyle.file

        for ssi in infos {
            let formattedSize = formatter.string(fromByteCount: Int64(ssi.size))
            print("| \(ssi.name) | \(formattedSize) |")
        }
    }
}
