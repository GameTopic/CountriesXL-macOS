// DownloadManagerV2.swift
// Manages async downloads with progress, pause/resume, cancel support
import Foundation
import Combine

@MainActor
final class DownloadManagerV2: ObservableObject {
    struct DownloadState {
        var progress: Double
        var isDownloading: Bool
        var isPaused: Bool
        var task: URLSessionDownloadTask?
        var resumeData: Data?
        var fileURL: URL?
    }
    
    static let shared = DownloadManagerV2()
    
    @Published private(set) var downloads: [Int: DownloadState] = [:]
    private var idToTitle: [Int: String] = [:]
    private var idToURL: [Int: URL] = [:]
    private var idToRequest: [Int: URLRequest] = [:]
    private var completionHandlers: [Int: (Result<URL, Error>) -> Void] = [:]
    private var idToCreated: [Int: Date] = [:]
    private var idToLastError: [Int: String] = [:]
    private var idToFileSize: [Int: Int64] = [:]
    private var progressObservations: [Int: NSKeyValueObservation] = [:]

    private let session: URLSession
    
    // Public accessors for UI sync
    func title(for id: Int) -> String? { idToTitle[id] }
    func setTitle(_ title: String?, for id: Int) {
        if let t = title, !t.isEmpty {
            idToTitle[id] = t
        } else {
            idToTitle[id] = nil
        }
        persistMeta()
    }
    func url(for id: Int) -> URL? { idToURL[id] }
    func fileURL(for id: Int) -> URL? { downloads[id]?.fileURL }
    
    func statusText(for id: Int) -> String {
        if let state = downloads[id] {
            if state.isDownloading { return "Downloading" }
            if state.isPaused { return "Paused" }
            if state.progress >= 1.0 { return "Completed" }
        }
        if let e = idToLastError[id], !e.isEmpty { return e }
        return "Idle"
    }
    
    // MARK: - File size accessors
    func setFileSize(_ bytes: Int64?, for id: Int) {
        if let b = bytes, b > 0 {
            idToFileSize[id] = b
        } else {
            idToFileSize[id] = nil
        }
        persistMeta()
    }

    func fileSizeText(for id: Int) -> String? {
        guard let bytes = idToFileSize[id] else { return nil }
        return Self.formatBytes(bytes)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let units: [String] = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1024.0 && idx < units.count - 1 {
            value /= 1024.0
            idx += 1
        }
        return String(format: "%.1f %@", value, units[idx])
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        restoreMeta()
    }

    private func destinationDirectory() throws -> (folder: URL, scopedURL: URL?, settings: SettingsStore?) {
        let settings = SettingsStore()
        let baseFolder: URL
        let scopedURL: URL?
        if let configuredFolder = settings.beginAccessingDownloadFolder() {
            baseFolder = configuredFolder
            scopedURL = configuredFolder
        } else {
            baseFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            scopedURL = nil
        }

        let folder = baseFolder.appendingPathComponent("CountriesXL", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return (folder, scopedURL, scopedURL == nil ? nil : settings)
    }
    
    func pauseDownload(id: Int) {
        guard let state = downloads[id], state.isDownloading, let task = state.task else { return }
        task.cancel { [weak self] resumeData in
            guard let self = self else { return }
            Task { @MainActor in
                self.downloads[id]?.isPaused = true
                self.downloads[id]?.isDownloading = false
                self.downloads[id]?.resumeData = resumeData
                self.downloads[id]?.task = nil
            }
        }
    }
    
    func cancelDownload(id: Int) {
        downloads[id]?.task?.cancel()
        downloads[id] = nil
        idToURL[id] = nil
        idToRequest[id] = nil
        idToTitle[id] = nil
        idToCreated[id] = nil
        idToLastError[id] = nil
        idToFileSize[id] = nil
        completionHandlers[id] = nil
        progressObservations[id] = nil
        persistMeta()
    }
    
    func clearDownload(id: Int) {
        downloads[id] = nil
        idToURL[id] = nil
        idToRequest[id] = nil
        idToTitle[id] = nil
        idToCreated[id] = nil
        idToLastError[id] = nil
        idToFileSize[id] = nil
        completionHandlers[id] = nil
        progressObservations[id] = nil
        persistMeta()
    }
    
    func progress(for id: Int) -> Double {
        downloads[id]?.progress ?? 0.0
    }
    
    func isDownloading(id: Int) -> Bool {
        downloads[id]?.isDownloading ?? false
    }
    
    func isPaused(id: Int) -> Bool {
        downloads[id]?.isPaused ?? false
    }
    
    // MARK: - Async/Await APIs
    
    func startDownload(id: Int, title: String, url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await startDownload(id: id, title: title, request: request, displayURL: url)
    }

    func startDownload(id: Int, title: String, request: URLRequest, displayURL: URL? = nil) async throws -> URL {
        if downloads[id]?.isDownloading == true {
            if let fileURL = downloads[id]?.fileURL {
                return fileURL
            } else {
                // If already downloading but no fileURL yet, wait for completion
                return try await withCheckedThrowingContinuation { continuation in
                    completionHandlers[id] = { result in
                        continuation.resume(with: result)
                    }
                }
            }
        }
        
        idToTitle[id] = title
        idToURL[id] = displayURL ?? request.url
        idToRequest[id] = request
        idToCreated[id] = Date()
        persistMeta()
        
        if let connected = NetworkMonitor.shared.isConnected, connected == false {
            throw URLError(.notConnectedToInternet)
        }
        if BoardStatusService.shared.isActive == false {
            throw NSError(domain: "BoardStatus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Board is inactive. Try again later."])
        }
        
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: URLError(.unknown))
                return
            }
            self.completionHandlers[id] = { result in
                continuation.resume(with: result)
            }
            let task = self.session.downloadTask(with: request) { [weak self] tempURL, response, error in
                Task { await self?.handleDownloadCompletion(id: id, tempURL: tempURL, response: response, error: error) }
            }
            self.downloads[id] = DownloadState(progress: 0.0, isDownloading: true, isPaused: false, task: task, resumeData: nil, fileURL: nil)
            self.idToLastError[id] = nil
            self.observeProgress(for: id, task: task)
            self.persistMeta()
            task.resume()
        }
    }
    
    func resumeDownload(id: Int) async throws -> URL {
        guard let state = downloads[id], state.isPaused, let resumeData = state.resumeData else {
            throw URLError(.unknown)
        }
        
        if let connected = NetworkMonitor.shared.isConnected, connected == false {
            throw URLError(.notConnectedToInternet)
        }
        if BoardStatusService.shared.isActive == false {
            throw NSError(domain: "BoardStatus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Board is inactive. Try again later."])
        }
        
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: URLError(.unknown))
                return
            }
            self.completionHandlers[id] = { result in
                continuation.resume(with: result)
            }
            let task = self.session.downloadTask(withResumeData: resumeData) { [weak self] tempURL, response, error in
                Task { await self?.handleDownloadCompletion(id: id, tempURL: tempURL, response: response, error: error) }
            }
            self.downloads[id]?.task = task
            self.downloads[id]?.isPaused = false
            self.downloads[id]?.isDownloading = true
            self.idToLastError[id] = nil
            self.observeProgress(for: id, task: task)
            self.persistMeta()
            task.resume()
        }
    }
    
    // MARK: - Helpers
    private func observeProgress(for id: Int, task: URLSessionDownloadTask) {
        progressObservations[id] = task.progress.observe(\.fractionCompleted) { [weak self] prog, _ in
            DispatchQueue.main.async {
                self?.downloads[id]?.progress = prog.fractionCompleted
            }
        }
    }
    
    private func handleDownloadCompletion(id: Int, tempURL: URL?, response: URLResponse?, error: Error?) async {
        if let tempURL {
            do {
                let destination = try destinationDirectory()
                defer { destination.settings?.endAccessingDownloadFolder(destination.scopedURL) }
                let filename = suggestedFilename(for: id, response: response, fallback: tempURL.lastPathComponent)
                let dest = destination.folder.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)

                downloads[id]?.fileURL = dest
                downloads[id]?.isDownloading = false
                downloads[id]?.isPaused = false
                downloads[id]?.progress = 1.0
                if let expected = response?.expectedContentLength, expected > 0 {
                    idToFileSize[id] = expected
                }
                idToLastError[id] = nil
                completionHandlers[id]?(.success(dest))
            } catch {
                downloads[id]?.isDownloading = false
                downloads[id]?.isPaused = false
                idToLastError[id] = (error as NSError).localizedDescription
                completionHandlers[id]?(.failure(error))
            }
        } else {
            downloads[id]?.isDownloading = false
            downloads[id]?.isPaused = false
            let err = error ?? URLError(.unknown)
            idToLastError[id] = (err as NSError).localizedDescription
            completionHandlers[id]?(.failure(err))
        }
        persistMeta()
        // Cleanup
        downloads[id]?.task = nil
        downloads[id]?.resumeData = nil
        completionHandlers[id] = nil
        progressObservations[id] = nil
    }

    private func suggestedFilename(for id: Int, response: URLResponse?, fallback: String) -> String {
        if let http = response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           let fileName = parseFilename(fromContentDisposition: disposition) {
            return fileName
        }

        if let suggested = response?.suggestedFilename, !suggested.isEmpty, suggested != "Unknown" {
            return suggested
        }

        if let current = idToURL[id]?.lastPathComponent, !current.isEmpty {
            return current
        }

        return fallback.isEmpty ? UUID().uuidString : fallback
    }

    private func parseFilename(fromContentDisposition header: String) -> String? {
        let patterns = [
            #"filename\*=UTF-8''([^;]+)"#,
            #"filename=\"([^\"]+)\""#,
            #"filename=([^;]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(header.startIndex..<header.endIndex, in: header)
            guard let match = regex.firstMatch(in: header, options: [], range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: header) else { continue }

            let rawValue = String(header[valueRange])
            let raw = rawValue
                .removingPercentEncoding?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespacesAndNewlines))
                ?? rawFallback(rawValue)

            if !raw.isEmpty {
                return raw
            }
        }

        return nil
    }

    private func rawFallback<S: StringProtocol>(_ value: S) -> String {
        String(value).trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespacesAndNewlines))
    }
    
    // MARK: - Persistence
    private func persistMeta() {
        // Convert keys to String for safe JSON serialization
        let titles = idToTitle.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }
        let created = idToCreated.reduce(into: [String: Double]()) { $0[String($1.key)] = $1.value.timeIntervalSince1970 }
        let errors = idToLastError.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }
        let sizes = idToFileSize.reduce(into: [String: NSNumber]()) { $0[String($1.key)] = NSNumber(value: $1.value) }
        let dict: [String: Any] = ["titles": titles, "created": created, "errors": errors, "sizes": sizes]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
            UserDefaults.standard.set(data, forKey: "DownloadManagerV2.meta")
        }
    }

    private func restoreMeta() {
        guard let data = UserDefaults.standard.data(forKey: "DownloadManagerV2.meta"),
              let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let titlesAny = any["titles"] as? [String: String] {
            self.idToTitle = titlesAny.reduce(into: [:]) { acc, pair in
                if let key = Int(pair.key) { acc[key] = pair.value }
            }
        }
        if let createdAny = any["created"] as? [String: Double] {
            self.idToCreated = createdAny.reduce(into: [:]) { acc, pair in
                if let key = Int(pair.key) { acc[key] = Date(timeIntervalSince1970: pair.value) }
            }
        }
        if let errorsAny = any["errors"] as? [String: String] {
            self.idToLastError = errorsAny.reduce(into: [:]) { acc, pair in
                if let key = Int(pair.key) { acc[key] = pair.value }
            }
        }
        if let sizesAny = any["sizes"] as? [String: Any] {
            var sizes: [Int: Int64] = [:]
            for (k, v) in sizesAny {
                guard let key = Int(k) else { continue }
                if let num = v as? NSNumber {
                    sizes[key] = num.int64Value
                } else if let d = v as? Double {
                    sizes[key] = Int64(d)
                } else if let i64 = v as? Int64 {
                    sizes[key] = i64
                } else if let i = v as? Int {
                    sizes[key] = Int64(i)
                }
            }
            self.idToFileSize = sizes
        }
    }
    
    // Sorted ids by creation date (most recent first)
    var sortedIds: [Int]? {
        guard !idToCreated.isEmpty else { return nil }
        return idToCreated.keys.sorted { (idToCreated[$0] ?? .distantPast) > (idToCreated[$1] ?? .distantPast) }
    }
}

extension DownloadManagerV2 {
    // Convenience static lookup when needed
    static func sharedTitle(for id: Int) -> String? {
        DownloadManagerV2.shared.title(for: id)
    }
}

#if os(macOS)
import AppKit
extension DownloadManagerV2 {
    func revealInFinder(for id: Int) {
        guard let url = fileURL(for: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
#endif
