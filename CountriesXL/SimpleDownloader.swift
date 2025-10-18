import Foundation

/// A tiny downloader that writes data into the user's selected download folder from SettingsStore.
/// This uses the security-scoped bookmark accessors exposed by SettingsStore.
struct SimpleDownloader {
    enum DownloadError: Error, LocalizedError {
        case noDestination
        case writeFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noDestination: return "No download destination is configured."
            case .writeFailed(let msg): return "Failed to write file: \(msg)"
            case .invalidResponse: return "Invalid network response."
            }
        }
    }

    let settings: SettingsStore

    /// Save raw data to a file name in the download folder.
    func save(data: Data, fileName: String) throws -> URL {
        guard let folder = settings.beginAccessingDownloadFolder() else {
            throw DownloadError.noDestination
        }
        defer { settings.endAccessingDownloadFolder(folder) }

        let destination = folder.appendingPathComponent(fileName, isDirectory: false)
        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            throw DownloadError.writeFailed(error.localizedDescription)
        }
    }

    /// Download a file from a URL and save it by the URL's lastPathComponent.
    func download(from url: URL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw DownloadError.invalidResponse
        }
        let fileName = url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent
        return try save(data: data, fileName: fileName)
    }
}
