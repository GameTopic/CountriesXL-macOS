import Foundation
import AVFoundation

// Mark API as requiring macOS 26+ as requested (use availability to avoid build-time mismatch on older SDKs)
@available(macOS 26, *)
actor DRMManagerActor {
    // Certificate cache and network helpers live inside the actor — Sendable-safe
    private var certificateCache: Data?

    init() {}

    func fetchCertificate(licenseURL: URL) async throws -> Data {
        if let cached = certificateCache { return cached }

        let candidates = ["certificate", "cert", "fairplay/certificate", "certificate.cer"]
        for c in candidates {
            let url = licenseURL.appendingPathComponent(c)
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode), !data.isEmpty {
                    certificateCache = data
                    return data
                }
            } catch {
                continue
            }
        }
        // As a last resort, try the license server root.
        let (data, resp) = try await URLSession.shared.data(from: licenseURL)
        if let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode), !data.isEmpty {
            certificateCache = data
            return data
        }
        throw URLError(.cannotLoadFromNetwork)
    }

    func requestCKC(spcData: Data, licenseURL: URL) async throws -> Data {
        var req = URLRequest(url: licenseURL)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = spcData

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode), !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// The delegate must be an NSObject to conform to AVContentKeySessionDelegate (Objective-C protocol).
@available(macOS 26, *)
final class DRMManager: NSObject, AVContentKeySessionDelegate, @unchecked Sendable {
    static let shared = DRMManager()

    private let actor = DRMManagerActor()
    private var keySession: AVContentKeySession?

    private override init() {
        super.init()
    }

    private func licenseServerConfigured() async -> Bool {
        await MainActor.run { () -> Bool in
            guard let s = SettingsService.shared.settings.drmLicenseEndpoint, !s.isEmpty else { return false }
            return URL(string: s) != nil
        }
    }

    // MARK: - AVContentKeySessionDelegate

    nonisolated func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        // Handle key request on the delegate (Obj-C) side; call into actor for network operations.
        Task { [weak self] in
            guard let self = self else { return }

            // Read license URL from MainActor-isolated SettingsService
            let licenseURLString = await MainActor.run { SettingsService.shared.settings.drmLicenseEndpoint }
            guard let licenseURLStringNonNil = licenseURLString, let licenseURL = URL(string: licenseURLStringNonNil) else {
                keyRequest.processContentKeyResponseError(URLError(.badURL))
                return
            }

            // Fetch certificate via actor
            do {
                let cert = try await self.actor.fetchCertificate(licenseURL: licenseURL)

                // Compute content identifier data
                let contentIdData: Data
                if let initData = keyRequest.initializationData, !initData.isEmpty {
                    contentIdData = initData
                } else if let assetID = keyRequest.identifier as? String, let d = assetID.data(using: .utf8) {
                    contentIdData = d
                } else {
                    contentIdData = Data()
                }

                let spc: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    keyRequest.makeStreamingContentKeyRequestData(forApp: cert, contentIdentifier: contentIdData, options: nil) { spcData, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        if let spcData = spcData {
                            continuation.resume(returning: spcData)
                        } else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                        }
                    }
                }

                // Request CKC using actor
                let ckc = try await self.actor.requestCKC(spcData: spc, licenseURL: licenseURL)
                let response = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc)
                keyRequest.processContentKeyResponse(response)

            } catch {
                keyRequest.processContentKeyResponseError(error)
            }
        }
    }

    nonisolated func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        contentKeySession(session, didProvide: keyRequest)
    }

    nonisolated func contentKeySession(_ session: AVContentKeySession, didFailWithError error: Error) {
        print("AVContentKeySession failed with error: \(error)")
    }

    // Public helper: create an AVPlayerItem for an HLS URL and register DRM session if configured
    func playerItemForURL(_ url: URL) async -> AVPlayerItem {
        let configured = await licenseServerConfigured()
        if !configured {
            return AVPlayerItem(url: url)
        }

        let asset = AVURLAsset(url: url)

        let (_, item): (AVContentKeySession, AVPlayerItem) = await MainActor.run {
            // Configure FairPlay key session on main actor
            let session: AVContentKeySession
            if let existing = self.keySession {
                session = existing
            } else {
                let newSession = AVContentKeySession(keySystem: .fairPlayStreaming)
                newSession.setDelegate(self, queue: DispatchQueue(label: "drm.keySession"))
                self.keySession = newSession
                session = newSession
            }

            session.addContentKeyRecipient(asset)
            let item = AVPlayerItem(asset: asset)
            return (session, item)
        }
        return item
    }
}
