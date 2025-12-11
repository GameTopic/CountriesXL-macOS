import Foundation

extension XenForoAPI {
    private var mediaRoutePrefix: String { UserDefaults.standard.string(forKey: "xf_media_route_prefix") ?? "media" }

    /// Attempts to discover a playback URL for a media item. Tries a few common API responses and falls back to constructing a direct path.
    func mediaPlaybackURL(id: Int, accessToken: String? = nil) async throws -> URL {
        // Common patterns: GET /media/{id}/play or /media/{id}/playback or /media/{id}
        let candidates = ["\(mediaRoutePrefix)/\(id)/playback", "\(mediaRoutePrefix)/\(id)/play", "\(mediaRoutePrefix)/\(id)"]
        for path in candidates {
            var req = try request(path: path)
            if let token = accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else { continue }
                if (200..<300).contains(http.statusCode) {
                    // Try parse JSON for common fields
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let urlString = json["playback_url"] as? String ?? json["download_url"] as? String ?? json["url"] as? String {
                            if let url = URL(string: urlString) { return url }
                        }
                    }
                    // If the endpoint returned a redirect, look for Location header
                    if let location = http.value(forHTTPHeaderField: "Location"), let url = URL(string: location) { return url }
                    // If response is not JSON but request URL itself might be the file
                    if let url = req.url { return url }
                }
            } catch {
                // try next
                continue
            }
        }
        // Fallback: assume direct path based on baseURL and prefix
        return baseURL.appendingPathComponent("\(mediaRoutePrefix)/\(id)/playback")
    }

    /// DRM-aware variant: attempt to request a DRM playback URL that may include tokenized HLS or otherwise protected streams.
    /// For now this mirrors mediaPlaybackURL but will hit a drm-specific path if available.
    func drmAwareMediaPlaybackURL(id: Int, accessToken: String? = nil) async throws -> URL {
        let candidates = ["\(mediaRoutePrefix)/\(id)/drm-playback", "\(mediaRoutePrefix)/\(id)/playback", "\(mediaRoutePrefix)/\(id)"]
        for path in candidates {
            var req = try request(path: path)
            if let token = accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else { continue }
                if (200..<300).contains(http.statusCode) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let urlString = json["drm_playback_url"] as? String ?? json["playback_url"] as? String ?? json["url"] as? String {
                            if let url = URL(string: urlString) { return url }
                        }
                    }
                    if let location = http.value(forHTTPHeaderField: "Location"), let url = URL(string: location) { return url }
                    if let url = req.url { return url }
                }
            } catch {
                continue
            }
        }
        // Fallback to generic playback URL
        return try await mediaPlaybackURL(id: id, accessToken: accessToken)
    }
}

