import Foundation

struct FileSkillHandler {
    static func handle(message: String) async -> String {
        let lower = message.lowercased()
        if lower.contains("list files") || lower.contains("desktop") {
            let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: desktopURL.path)
                // Filter out hidden files
                let visibleFiles = files.filter { !$0.hasPrefix(".") }
                if visibleFiles.isEmpty {
                    return "Your Desktop is currently empty."
                }
                return "Files on your Desktop:\n" + visibleFiles.joined(separator: "\n")
            } catch {
                return "Error reading Desktop: \(error.localizedDescription)"
            }
        }
        // Add more file operations as needed
        return "Could not process file request."
    }
}
