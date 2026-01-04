import Foundation

func saveDebugDataToTempFile(description: String, fileName: String, data: Data) {
    #if DEBUG
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let responseFile = tempDir.appendingPathComponent(fileName)
            try data.write(to: responseFile)
            print("💾 DEBUG: \(description) saved to: \(responseFile.path)")
        } catch {
            print("💾 DEBUG: \(description) failed to save")
        }
    #endif
}
