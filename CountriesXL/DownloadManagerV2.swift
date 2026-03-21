// DownloadManagerV2.swift
// Manages async downloads with progress, pause/resume, cancel support
import Foundation
import Combine
#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
final class DownloadManagerV2: ObservableObject {
    public enum DownloadKind: String, Codable, CaseIterable {
        case generic
        case resource
        case media
        case image
        case video
        case audio
        case thread
        case attachment

        var title: String {
            switch self {
            case .generic: return "Other"
            case .resource: return "Resources"
            case .media: return "Media"
            case .image: return "Images"
            case .video: return "Videos"
            case .audio: return "Audio"
            case .thread: return "Threads"
            case .attachment: return "Attachments"
            }
        }

        var symbolName: String {
            switch self {
            case .generic: return "tray"
            case .resource: return "shippingbox"
            case .media: return "photo.on.rectangle"
            case .image: return "photo"
            case .video: return "play.rectangle"
            case .audio: return "waveform"
            case .thread: return "text.bubble"
            case .attachment: return "paperclip"
            }
        }
    }

    public struct DownloadDescriptor {
        public let kind: DownloadKind
        public let sourceTitle: String?

        public init(kind: DownloadKind = .generic, sourceTitle: String? = nil) {
            self.kind = kind
            self.sourceTitle = sourceTitle
        }
    }

    struct DownloadState {
        var progress: Double
        var isPreparing: Bool
        var isQueued: Bool
        var isDownloading: Bool
        var isPaused: Bool
        var task: URLSessionDownloadTask?
        var resumeData: Data?
        var fileURL: URL?
    }

    struct DownloadAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
    
    static let shared = DownloadManagerV2()
    
    @Published private(set) var downloads: [Int: DownloadState] = [:]
    private var idToTitle: [Int: String] = [:]
    private var idToURL: [Int: URL] = [:]
    private var idToRequest: [Int: URLRequest] = [:]
    private var idToFileURL: [Int: URL] = [:]
    private var idToDestinationOverride: [Int: URL] = [:]
    private var idToKind: [Int: DownloadKind] = [:]
    private var idToSourceTitle: [Int: String] = [:]
    private var completionHandlers: [Int: (Result<URL, Error>) -> Void] = [:]
    private var idToCreated: [Int: Date] = [:]
    private var idToLastError: [Int: String] = [:]
    private var idToFileSize: [Int: Int64] = [:]
    private var progressObservations: [Int: NSKeyValueObservation] = [:]

    private let session: URLSession
    @Published var activeAlert: DownloadAlert?
    
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
    func fileURL(for id: Int) -> URL? { downloads[id]?.fileURL ?? idToFileURL[id] }
    func kind(for id: Int) -> DownloadKind { idToKind[id] ?? .generic }
    func sourceTitle(for id: Int) -> String? { idToSourceTitle[id] }

    var knownDownloadIDs: [Int] {
        let allIDs = Set(downloads.keys)
            .union(idToTitle.keys)
            .union(idToURL.keys)
            .union(idToFileURL.keys)
            .union(idToKind.keys)
            .union(idToSourceTitle.keys)
            .union(idToCreated.keys)
            .union(idToLastError.keys)
            .union(idToFileSize.keys)
        guard !allIDs.isEmpty else { return [] }
        return allIDs.sorted { (idToCreated[$0] ?? .distantPast) > (idToCreated[$1] ?? .distantPast) }
    }

    var hasKnownDownloads: Bool {
        !knownDownloadIDs.isEmpty
    }

    func isCompleted(id: Int) -> Bool {
        if let state = downloads[id], state.progress >= 1.0 {
            return true
        }
        return fileURL(for: id) != nil
    }
    
    func statusText(for id: Int) -> String {
        if let state = downloads[id] {
            if state.isPreparing { return "Preparing" }
            if state.isQueued { return "Ready to save" }
            if state.isDownloading { return "Downloading" }
            if state.isPaused { return "Paused" }
            if state.progress >= 1.0 { return "Completed" }
        }
        if fileURL(for: id) != nil { return "Completed" }
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
        idToFileURL[id] = nil
        idToDestinationOverride[id] = nil
        idToKind[id] = nil
        idToSourceTitle[id] = nil
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
        idToFileURL[id] = nil
        idToDestinationOverride[id] = nil
        idToKind[id] = nil
        idToSourceTitle[id] = nil
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

    func isQueued(id: Int) -> Bool {
        downloads[id]?.isQueued ?? false
    }

    func isPreparing(id: Int) -> Bool {
        downloads[id]?.isPreparing ?? false
    }
    
    func isDownloading(id: Int) -> Bool {
        downloads[id]?.isDownloading ?? false
    }
    
    func isPaused(id: Int) -> Bool {
        downloads[id]?.isPaused ?? false
    }
    
    // MARK: - Async/Await APIs
    
    func prepareDownload(id: Int, title: String, displayURL: URL? = nil, descriptor: DownloadDescriptor = DownloadDescriptor()) {
        if let existingState = downloads[id] {
            if existingState.isPreparing || existingState.isQueued || existingState.isDownloading || existingState.isPaused {
                NotificationCenter.default.post(name: .openDownloads, object: nil)
                return
            }
        }
        if let existingID = existingCompletedDownloadID(for: displayURL, preferredID: id) {
            let existingTitle = idToTitle[existingID] ?? title
            activeAlert = DownloadAlert(
                title: "Download Already Completed",
                message: "\(existingTitle) has already been completed."
            )
            NotificationCenter.default.post(name: .openDownloads, object: nil)
            return
        }

        idToTitle[id] = title
        idToURL[id] = displayURL
        idToRequest[id] = nil
        idToFileURL[id] = nil
        idToDestinationOverride[id] = nil
        idToKind[id] = descriptor.kind
        if let sourceTitle = descriptor.sourceTitle, !sourceTitle.isEmpty {
            idToSourceTitle[id] = sourceTitle
        } else {
            idToSourceTitle[id] = nil
        }
        idToCreated[id] = Date()
        idToLastError[id] = nil
        downloads[id] = DownloadState(progress: 0.0, isPreparing: true, isQueued: false, isDownloading: false, isPaused: false, task: nil, resumeData: nil, fileURL: nil)
        persistMeta()
    }

    func configurePreparedDownload(id: Int, request: URLRequest, displayURL: URL? = nil) {
        guard downloads[id] != nil else { return }
        idToRequest[id] = request
        if let displayURL {
            idToURL[id] = displayURL
        } else if let requestURL = request.url {
            idToURL[id] = requestURL
        }
        downloads[id]?.isPreparing = false
        downloads[id]?.isQueued = true
        idToLastError[id] = nil
        persistMeta()
    }

    func failPreparedDownload(id: Int, error: Error) {
        guard downloads[id] != nil else { return }
        downloads[id]?.isPreparing = false
        downloads[id]?.isQueued = false
        downloads[id]?.isDownloading = false
        downloads[id]?.isPaused = false
        idToLastError[id] = error.localizedDescription
        persistMeta()
    }

    func canStartQueuedDownload(id: Int) -> Bool {
        idToRequest[id] != nil
    }

    func queueDownload(id: Int, title: String, url: URL, descriptor: DownloadDescriptor = DownloadDescriptor()) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        queueDownload(id: id, title: title, request: request, displayURL: url, descriptor: descriptor)
    }

    func queueDownload(id: Int, title: String, request: URLRequest, displayURL: URL? = nil, descriptor: DownloadDescriptor = DownloadDescriptor()) {
        if let existingID = existingCompletedDownloadID(for: displayURL ?? request.url, preferredID: id) {
            let existingTitle = idToTitle[existingID] ?? title
            activeAlert = DownloadAlert(
                title: "Download Already Completed",
                message: "\(existingTitle) has already been completed."
            )
            NotificationCenter.default.post(name: .openDownloads, object: nil)
            return
        }

        prepareDownload(id: id, title: title, displayURL: displayURL ?? request.url, descriptor: descriptor)
        configurePreparedDownload(id: id, request: request, displayURL: displayURL ?? request.url)
    }

    func startDownload(id: Int, title: String, url: URL, descriptor: DownloadDescriptor = DownloadDescriptor()) async throws -> URL {
        queueDownload(id: id, title: title, url: url, descriptor: descriptor)
        return try await startQueuedDownload(id: id)
    }

    func startDownload(id: Int, title: String, request: URLRequest, displayURL: URL? = nil, descriptor: DownloadDescriptor = DownloadDescriptor()) async throws -> URL {
        queueDownload(id: id, title: title, request: request, displayURL: displayURL, descriptor: descriptor)
        return try await startQueuedDownload(id: id)
    }

    func startQueuedDownload(id: Int, destinationOverride: URL? = nil) async throws -> URL {
        if downloads[id]?.isDownloading == true {
            if let fileURL = downloads[id]?.fileURL {
                return fileURL
            } else {
                return try await withCheckedThrowingContinuation { continuation in
                    completionHandlers[id] = { result in
                        continuation.resume(with: result)
                    }
                }
            }
        }

        guard let request = idToRequest[id] else {
            throw URLError(.badURL)
        }

        if let destinationOverride {
            idToDestinationOverride[id] = destinationOverride
        }

        if let sourceURL = request.url, sourceURL.isFileURL {
            return try await completeLocalFileDownload(id: id, sourceURL: sourceURL)
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
            let task = self.session.downloadTask(with: request) { [weak self] tempURL, response, error in
                Task { await self?.handleDownloadCompletion(id: id, tempURL: tempURL, response: response, error: error) }
            }
            self.downloads[id] = DownloadState(progress: 0.0, isPreparing: false, isQueued: false, isDownloading: true, isPaused: false, task: task, resumeData: nil, fileURL: self.idToFileURL[id])
            self.idToLastError[id] = nil
            self.observeProgress(for: id, task: task)
            self.persistMeta()
            task.resume()
        }
    }

    private func completeLocalFileDownload(id: Int, sourceURL: URL) async throws -> URL {
        downloads[id] = DownloadState(
            progress: 0.0,
            isPreparing: false,
            isQueued: false,
            isDownloading: true,
            isPaused: false,
            task: nil,
            resumeData: nil,
            fileURL: downloads[id]?.fileURL ?? idToFileURL[id]
        )
        idToLastError[id] = nil
        persistMeta()

        do {
            let filename = sourceURL.lastPathComponent
            let destinationURL: URL
            if let override = idToDestinationOverride[id] {
                destinationURL = override
            } else {
                let destination = try destinationDirectory()
                defer { destination.settings?.endAccessingDownloadFolder(destination.scopedURL) }
                destinationURL = destination.folder.appendingPathComponent(filename)
            }

            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value
            downloads[id]?.fileURL = destinationURL
            downloads[id]?.isDownloading = false
            downloads[id]?.isPaused = false
            downloads[id]?.progress = 1.0
            idToFileURL[id] = destinationURL
            if let fileSize, fileSize > 0 {
                idToFileSize[id] = fileSize
            }
            idToLastError[id] = nil
            persistMeta()
            await postCompletionNotification(for: id, fileURL: destinationURL)
            return destinationURL
        } catch {
            downloads[id]?.isDownloading = false
            downloads[id]?.isPaused = false
            idToLastError[id] = (error as NSError).localizedDescription
            persistMeta()
            throw error
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
            self.downloads[id]?.isPreparing = false
            self.downloads[id]?.isQueued = false
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
                let filename = suggestedFilename(for: id, response: response, fallback: tempURL.lastPathComponent)
                let dest: URL
                if let override = idToDestinationOverride[id] {
                    dest = override
                } else {
                    let destination = try destinationDirectory()
                    defer { destination.settings?.endAccessingDownloadFolder(destination.scopedURL) }
                    dest = destination.folder.appendingPathComponent(filename)
                }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)

                downloads[id]?.fileURL = dest
                downloads[id]?.isPreparing = false
                downloads[id]?.isQueued = false
                idToFileURL[id] = dest
                downloads[id]?.isDownloading = false
                downloads[id]?.isPaused = false
                downloads[id]?.progress = 1.0
                if let expected = response?.expectedContentLength, expected > 0 {
                    idToFileSize[id] = expected
                }
                idToLastError[id] = nil
                await postCompletionNotification(for: id, fileURL: dest)
                completionHandlers[id]?(.success(dest))
            } catch {
                downloads[id]?.isPreparing = false
                downloads[id]?.isQueued = false
                downloads[id]?.isDownloading = false
                downloads[id]?.isPaused = false
                idToLastError[id] = (error as NSError).localizedDescription
                completionHandlers[id]?(.failure(error))
            }
        } else {
            downloads[id]?.isPreparing = false
            downloads[id]?.isQueued = false
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

    private func existingCompletedDownloadID(for url: URL?, preferredID: Int) -> Int? {
        if isCompleted(id: preferredID) {
            return preferredID
        }
        for existingID in knownDownloadIDs {
            guard isCompleted(id: existingID) else { continue }
            if let existingURL = idToURL[existingID], let url, existingURL == url {
                return existingID
            }
        }
        return nil
    }

    @MainActor
    private func postCompletionNotification(for id: Int, fileURL: URL) async {
        #if os(macOS)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return
        }
        guard let notificationCenter = NSClassFromString("UNUserNotificationCenter") else { return }
        _ = notificationCenter
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let content = UNMutableNotificationContent()
        content.title = "Download Completed"
        content.body = "\(idToTitle[id] ?? fileURL.lastPathComponent) is ready."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "CountriesXL.download.\(id)", content: content, trigger: nil)
        try? await center.add(request)
        #endif
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
        let urls = idToURL.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value.absoluteString }
        let fileURLs = idToFileURL.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value.path }
        let destinationOverrides = idToDestinationOverride.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value.path }
        let kinds = idToKind.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value.rawValue }
        let sourceTitles = idToSourceTitle.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }
        let dict: [String: Any] = ["titles": titles, "created": created, "errors": errors, "sizes": sizes, "urls": urls, "fileURLs": fileURLs, "destinationOverrides": destinationOverrides, "kinds": kinds, "sourceTitles": sourceTitles]
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
        if let urlsAny = any["urls"] as? [String: String] {
            self.idToURL = urlsAny.reduce(into: [:]) { acc, pair in
                guard let key = Int(pair.key), let url = URL(string: pair.value) else { return }
                acc[key] = url
            }
        }
        if let fileURLsAny = any["fileURLs"] as? [String: String] {
            self.idToFileURL = fileURLsAny.reduce(into: [:]) { acc, pair in
                guard let key = Int(pair.key) else { return }
                acc[key] = URL(fileURLWithPath: pair.value)
            }
        }
        if let destinationOverridesAny = any["destinationOverrides"] as? [String: String] {
            self.idToDestinationOverride = destinationOverridesAny.reduce(into: [:]) { acc, pair in
                guard let key = Int(pair.key) else { return }
                acc[key] = URL(fileURLWithPath: pair.value)
            }
        }
        if let kindsAny = any["kinds"] as? [String: String] {
            self.idToKind = kindsAny.reduce(into: [:]) { acc, pair in
                guard let key = Int(pair.key), let kind = DownloadKind(rawValue: pair.value) else { return }
                acc[key] = kind
            }
        }
        if let sourceTitlesAny = any["sourceTitles"] as? [String: String] {
            self.idToSourceTitle = sourceTitlesAny.reduce(into: [:]) { acc, pair in
                guard let key = Int(pair.key) else { return }
                acc[key] = pair.value
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
        let ids = knownDownloadIDs
        return ids.isEmpty ? nil : ids
    }
}

extension DownloadManagerV2 {
    // Convenience static lookup when needed
    static func sharedTitle(for id: Int) -> String? {
        DownloadManagerV2.shared.title(for: id)
    }
}

#if DEBUG
extension DownloadManagerV2 {
    func resetForTesting() {
        let ids = knownDownloadIDs
        ids.forEach { clearDownload(id: $0) }
        activeAlert = nil
    }

    func seedPreparedDownloadForTesting(
        id: Int = 9_001,
        title: String = "UITest Resource",
        url: URL = URL(string: "https://example.com/uitest-resource.zip")!,
        descriptor: DownloadDescriptor = .init(kind: .resource, sourceTitle: "UI Test")
    ) {
        resetForTesting()
        prepareDownload(id: id, title: title, displayURL: url, descriptor: descriptor)
    }

    func seedQueuedDownloadForTesting(
        id: Int = 9_002,
        title: String = "UITest Queued Resource",
        url: URL = URL(string: "https://example.com/queued-resource.zip")!,
        descriptor: DownloadDescriptor = .init(kind: .resource, sourceTitle: "UI Test")
    ) {
        resetForTesting()
        prepareDownload(id: id, title: title, displayURL: url, descriptor: descriptor)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        configurePreparedDownload(id: id, request: request, displayURL: url)
    }

    func seedCompletedDownloadForTesting(
        id: Int = 9_003,
        title: String = "UITest Completed Resource",
        fileExtension: String = "zip",
        descriptor: DownloadDescriptor = .init(kind: .resource, sourceTitle: "UI Test")
    ) {
        resetForTesting()

        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("CountriesXL-UITests", isDirectory: true)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("\(title.replacingOccurrences(of: " ", with: "-")).\(fileExtension)")
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: Data("ui-test".utf8))
        }

        idToTitle[id] = title
        idToURL[id] = fileURL
        idToRequest[id] = URLRequest(url: fileURL)
        idToFileURL[id] = fileURL
        idToDestinationOverride[id] = nil
        idToKind[id] = descriptor.kind
        idToSourceTitle[id] = descriptor.sourceTitle
        idToCreated[id] = Date()
        idToLastError[id] = nil
        downloads[id] = DownloadState(
            progress: 1.0,
            isPreparing: false,
            isQueued: false,
            isDownloading: false,
            isPaused: false,
            task: nil,
            resumeData: nil,
            fileURL: fileURL
        )
        persistMeta()
    }
}
#endif

#if os(macOS)
import AppKit
extension DownloadManagerV2 {
    func actionTitle(for id: Int) -> String {
        guard let url = fileURL(for: id) else { return "Run" }
        switch url.pathExtension.lowercased() {
        case "pkg", "mpkg", "dmg":
            return "Install"
        default:
            return "Run"
        }
    }

    func openDownloadedFile(for id: Int) {
        guard let url = fileURL(for: id) else { return }
        NSWorkspace.shared.open(url)
    }

    func saveDownloadAs(for id: Int) {
        guard let sourceURL = fileURL(for: id) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let destinationURL = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                self?.activeAlert = DownloadAlert(
                    title: "File Saved",
                    message: "\(sourceURL.lastPathComponent) was saved to the selected location."
                )
            } catch {
                self?.activeAlert = DownloadAlert(
                    title: "Save As Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func startQueuedDownloadWithSavePanel(for id: Int) async {
        guard let suggestedURL = fileURL(for: id) ?? url(for: id) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let destinationURL = panel.url else { return }
            Task { @MainActor in
                do {
                    _ = try await self?.startQueuedDownload(id: id, destinationOverride: destinationURL)
                } catch {
                    self?.activeAlert = DownloadAlert(
                        title: "Download Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    func deleteDownloadedFile(for id: Int) {
        guard let url = fileURL(for: id) else {
            clearDownload(id: id)
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
            clearDownload(id: id)
        } catch {
            activeAlert = DownloadAlert(
                title: "Delete Failed",
                message: error.localizedDescription
            )
        }
    }

    func revealInFinder(for id: Int) {
        guard let url = fileURL(for: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
#endif
