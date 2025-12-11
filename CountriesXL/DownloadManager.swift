import Foundation

actor DownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    struct Item: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        var filename: String { url.lastPathComponent }
        var progress: Double = 0
        var completed: Bool = false
        var isDownloading: Bool = false
        var paused: Bool = false
        var totalBytesWritten: Int64 = 0
        var totalBytesExpected: Int64? = nil
        var startedAt: Date? = nil
        var localFileURL: URL? = nil
        var errorDescription: String? = nil
    }

    private(set) var items: [Item] = []
    private var taskForURL: [URL: URLSessionDownloadTask] = [:]
    private var resumeDataForURL: [URL: Data] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private func destinationDirectory() throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let folder = downloads.appendingPathComponent("CountriesXL", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    func enqueue(url: URL) {
        items.append(Item(url: url))
        if let idx = items.firstIndex(where: { $0.url == url }) {
            items[idx].isDownloading = true
            items[idx].paused = false
            items[idx].completed = false
            items[idx].errorDescription = nil
            items[idx].progress = 0
            items[idx].totalBytesWritten = 0
            items[idx].totalBytesExpected = nil
            items[idx].startedAt = Date()
        }
        let task = session.downloadTask(with: url)
        taskForURL[url] = task
        task.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { [totalBytesWritten, totalBytesExpectedToWrite, weak self] in
            guard let self else { return }
            await self.updateProgress(for: downloadTask.originalRequest?.url, written: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { [location, weak self] in
            guard let self else { return }
            let srcURL = downloadTask.originalRequest?.url
            do {
                let folder = try await self.destinationDirectory()
                let filename = downloadTask.originalRequest?.url?.lastPathComponent ?? UUID().uuidString
                let dest = folder.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: location, to: dest)
                await self.markCompleted(for: srcURL, localURL: dest)
                if let u = srcURL {
                    await self.clearTaskAndResumeData(for: u)
                }
            } catch {
                await self.markFailed(for: srcURL, error: error)
            }
        }
    }

    // MARK: - Controls
    func pause(url: URL) {
        guard let task = taskForURL[url] else { return }
        task.cancel(byProducingResumeData: { data in
            Task { [weak self] in
                guard let self else { return }
                await self.setPaused(true, for: url)
                await self.setResumeData(data, for: url)
                await self.setTask(nil, for: url)
            }
        })
    }

    func resume(url: URL) {
        guard let data = resumeDataForURL[url] else { return }
        let task = session.downloadTask(withResumeData: data)
        taskForURL[url] = task
        Task { [weak self] in
            guard let self else { return }
            await self.setPaused(false, for: url)
            await self.setDownloading(true, for: url)
        }
        task.resume()
    }

    func cancel(url: URL) {
        taskForURL[url]?.cancel()
        taskForURL[url] = nil
        resumeDataForURL[url] = nil
        setCancelled(for: url)
    }

    func clear(url: URL) {
        if let idx = items.firstIndex(where: { $0.url == url }) {
            items.remove(at: idx)
        }
    }

    func clearAll() {
        items.removeAll()
        taskForURL.removeAll()
        resumeDataForURL.removeAll()
    }

    // MARK: - Helpers

    private func updateProgress(for url: URL?, written: Int64, expected: Int64) {
        guard let url, let idx = items.firstIndex(where: { $0.url == url }) else { return }
        items[idx].totalBytesWritten = written
        items[idx].totalBytesExpected = expected > 0 ? expected : nil
        if let exp = items[idx].totalBytesExpected, exp > 0 {
            items[idx].progress = Double(written) / Double(exp)
        } else {
            items[idx].progress = 0
        }
    }

    private func markCompleted(for url: URL?, localURL: URL) {
        guard let url, let idx = items.firstIndex(where: { $0.url == url }) else { return }
        items[idx].completed = true
        items[idx].localFileURL = localURL
        if let exp = items[idx].totalBytesExpected, exp > 0 {
            items[idx].totalBytesWritten = exp
            items[idx].progress = 1.0
        } else {
            items[idx].progress = 1.0
        }
        items[idx].isDownloading = false
        items[idx].paused = false
    }

    private func markFailed(for url: URL?, error: Error) {
        guard let url, let idx = items.firstIndex(where: { $0.url == url }) else { return }
        items[idx].errorDescription = error.localizedDescription
        items[idx].isDownloading = false
        items[idx].paused = false
    }

    private func setPaused(_ paused: Bool, for url: URL) {
        if let idx = items.firstIndex(where: { $0.url == url }) {
            items[idx].paused = paused
            items[idx].isDownloading = !paused
        }
    }

    private func setDownloading(_ downloading: Bool, for url: URL) {
        if let idx = items.firstIndex(where: { $0.url == url }) {
            items[idx].isDownloading = downloading
            if downloading { items[idx].paused = false }
        }
    }

    private func setCancelled(for url: URL) {
        if let idx = items.firstIndex(where: { $0.url == url }) {
            items[idx].isDownloading = false
            items[idx].paused = false
            if !items[idx].completed {
                items[idx].errorDescription = "Cancelled"
            }
        }
    }

    private func clearTaskAndResumeData(for url: URL) {
        taskForURL[url] = nil
        resumeDataForURL[url] = nil
    }

    private func setResumeData(_ data: Data?, for url: URL) {
        if let data {
            resumeDataForURL[url] = data
        }
    }

    private func setTask(_ task: URLSessionDownloadTask?, for url: URL) {
        taskForURL[url] = task
    }
}
