import Foundation
import SwiftUI

// Simple BBCode parser for common XenForo 2.3 tags.
// Converts BBCode into AttributedString for display in SwiftUI/Text or NSAttributedString if needed.
// This is intentionally small and deterministic — it handles: b, i, u, url, img (as alt text), quote, code, list, *

public enum BBCodeParser {
    // Represent a discovered embedded media item so views can render it as a separate view.
    public struct Embed: Identifiable, Hashable {
        public enum Kind: String, Codable {
            case youtube
            case url
            case xenforoMedia
            case unknown
        }
        public let id = UUID()
        public let kind: Kind
        public let identifier: String // e.g. YouTube video id, or URL string, or media id
        public let provider: String? // optional provider hint
        public var url: URL? { URL(string: identifier) }
    }

    @MainActor public static func attributedString(from bbcode: String, baseFont: Font = .body) -> AttributedString {
        var working = bbcode

        // Handle code blocks first to avoid parsing inner tags
        let codePattern = #"(?s)\[code\](.*?)\[/code\]"#
        let codeMatches = regexMatches(pattern: codePattern, in: working)
        var codeTokens: [String] = []
        for (i, match) in codeMatches.enumerated() {
            let range = match.range(at: 0)
            let ns = working as NSString
            let block = ns.substring(with: range)
            let token = "__BB_CODE_BLOCK_\(i)__"
            codeTokens.append(block)
            working = (working as NSString).replacingCharacters(in: range, with: token)
        }

        // Simple inline replacements
        working = working.replacingOccurrences(of: "[b]", with: "**")
        working = working.replacingOccurrences(of: "[/b]", with: "**")
        working = working.replacingOccurrences(of: "[i]", with: "*")
        working = working.replacingOccurrences(of: "[/i]", with: "*")
        // Underline: mark tokens and apply later
        working = working.replacingOccurrences(of: "[u]", with: "__BB_U_START__")
        working = working.replacingOccurrences(of: "[/u]", with: "__BB_U_END__")

        // URLs
        working = regexReplace(pattern: "\\[url=(.*?)\\](.*?)\\[/url\\]", in: working) { groups in
            // groups[0] full match, groups[1] = url, groups[2] = text
            let url = groups.count > 1 ? groups[1] : ""
            let text = groups.count > 2 ? groups[2] : url
            return "[\(text)](\(url))"
        }
        working = regexReplace(pattern: "\\[url\\](.*?)\\[/url\\]", in: working) { groups in
            let url = groups.count > 1 ? groups[1] : ""
            return "[\(url)](\(url))"
        }

        // Images -> inline alt text
        working = regexReplace(pattern: "\\[img\\](.*?)\\[/img\\]", in: working) { groups in
            let img = groups.count > 1 ? groups[1] : ""
            return "[image: \(img)]"
        }

        // Quote -> prepend > to each line
        working = regexReplace(pattern: "(?s)\\[quote(?:=.*?)?\\](.*?)\\[/quote\\]", in: working) { groups in
            let body = groups.count > 1 ? groups[1] : ""
            let quoted = body.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
            return quoted
        }

        // Lists
        working = regexReplace(pattern: "(?s)\\[list\\](.*?)\\[/list\\]", in: working) { groups in
            let body = groups.count > 1 ? groups[1] : ""
            let items = regexCaptureAll(pattern: "\\[\\*\\](.*?)($|\\n)", in: body)
            if items.isEmpty {
                return body.split(separator: "\n").map { "• \($0)" }.joined(separator: "\n")
            } else {
                return items.map { "• \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }.joined(separator: "\n")
            }
        }

        // Remaining [*]
        working = regexReplace(pattern: "\\[\\*\\]", in: working) { _ in "• " }

        // Restore code blocks as fenced blocks
        for (i, tokenBlock) in codeTokens.enumerated() {
            let token = "__BB_CODE_BLOCK_\(i)__"
            // strip the [code]...[/code]
            let inner = tokenBlock.replacingOccurrences(of: "[code]", with: "").replacingOccurrences(of: "[/code]", with: "")
            working = working.replacingOccurrences(of: token, with: "```\n\(inner)\n```")
        }

        // Convert to AttributedString via Markdown when possible
        if let attributedFromMarkdown = try? AttributedString(markdown: working) {
            var final = attributedFromMarkdown
            applyUnderlineRanges(original: bbcode, target: &final)
            return final
        }

        return AttributedString(bbcode)
    }

    // Extract embedded media (YouTube links, [media] tags, generic URLs) so the hosting view can render them as media views.
    public static func extractEmbeds(from bbcode: String) -> [Embed] {
        var results: [Embed] = []
        // 1) XenForo [media]...[/media] or [media=provider]id[/media]
        let mediaPattern = "(?i)\\[media(?:=(.*?))?\\](.*?)\\[/media\\]"
        let mediaMatches = regexMatches(pattern: mediaPattern, in: bbcode)
        for m in mediaMatches {
            let ns = bbcode as NSString
            // group 1 = optional provider, group 2 = content
            var provider = ""
            var content = ""
            if m.numberOfRanges > 1 {
                let r1 = m.range(at: 1)
                if r1.location != NSNotFound { provider = ns.substring(with: r1) }
            }
            if m.numberOfRanges > 2 {
                let r2 = m.range(at: 2)
                if r2.location != NSNotFound { content = ns.substring(with: r2) }
            }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = Int(trimmed) {
                results.append(Embed(kind: .xenforoMedia, identifier: String(id), provider: provider.isEmpty ? nil : provider))
            } else if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
                results.append(Embed(kind: .url, identifier: trimmed, provider: provider.isEmpty ? nil : provider))
            } else if !trimmed.isEmpty {
                // fallback string identifier
                results.append(Embed(kind: .unknown, identifier: trimmed, provider: provider.isEmpty ? nil : provider))
            }
        }

        // 2) YouTube links (regular and youtu.be shortlinks)
        let youTubePatterns = ["https?://(?:www\\.)?youtube\\.com/watch\\?v=([A-Za-z0-9_-]{6,})","https?://youtu\\.be/([A-Za-z0-9_-]{6,})"]
        for pat in youTubePatterns {
            let matches = regexMatches(pattern: pat, in: bbcode)
            for m in matches {
                let ns = bbcode as NSString
                if m.numberOfRanges > 1 {
                    let r = m.range(at: 1)
                    if r.location != NSNotFound {
                        let id = ns.substring(with: r)
                        results.append(Embed(kind: .youtube, identifier: id, provider: "youtube"))
                    }
                }
            }
        }

        // 3) Generic explicit URLs in their own [url] tags are already converted to inline markdown by the main parser,
        // but detect other bare URLs for embed candidates (simple heuristic)
        let urlPattern = #"https?://[\w./?&=%-]+"#
        let urlMatches = regexMatches(pattern: urlPattern, in: bbcode)
        for m in urlMatches {
            let ns = bbcode as NSString
            let r = m.range(at: 0)
            if r.location != NSNotFound {
                let s = ns.substring(with: r)
                // skip duplicates and ones we've already added (youtube)
                if !results.contains(where: { $0.identifier == s }) {
                    results.append(Embed(kind: .url, identifier: s, provider: nil))
                }
            }
        }

        return results
    }

    // MARK: - Helpers
    private static func applyUnderlineRanges(original: String, target: inout AttributedString) {
        let pattern = "(?s)\\[u\\](.*?)\\[/u\\]"
        let matches = regexMatches(pattern: pattern, in: original)
        for m in matches {
            let ns = original as NSString
            let r = m.range(at: 1)
            if r.location != NSNotFound {
                let inner = ns.substring(with: r)
                if let range = target.range(of: inner) {
                    var attrs = AttributeContainer()
                    attrs.underlineStyle = .single
                    target[range].setAttributes(attrs)
                }
            }
        }
    }

    private static func regexMatches(pattern: String, in text: String) -> [NSTextCheckingResult] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
            let ns = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            return results
        } catch {
            return []
        }
    }

    private static func regexReplace(pattern: String, in text: String, transform: ([String]) -> String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let ns = text as NSString
            var result = text
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                var groups: [String] = []
                for i in 0..<m.numberOfRanges {
                    let r = m.range(at: i)
                    if r.location != NSNotFound {
                        groups.append(ns.substring(with: r))
                    } else {
                        groups.append("")
                    }
                }
                let replacement = transform(groups)
                result = (result as NSString).replacingCharacters(in: m.range, with: replacement)
            }
            return result
        } catch {
            return text
        }
    }

    private static func regexCaptureAll(pattern: String, in text: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let ns = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            return results.compactMap { r in
                if r.numberOfRanges >= 2 {
                    let r1 = r.range(at: 1)
                    if r1.location != NSNotFound {
                        return ns.substring(with: r1)
                    }
                }
                return nil
            }
        } catch {
            return []
        }
    }
}

// MARK: - Remote rendering helper
extension BBCodeParser {
    /// Attempts to render BBCode on a remote endpoint if configured (SettingsService.shared.settings.remoteRenderEndpoint),
    /// otherwise falls back to local rendering.
    /// The remote endpoint is expected to accept a POST with JSON body { "bbcode": "..." }
    /// and return JSON with { "html": "<rendered>...</rendered>" } or { "rendered": "..." }.
    @MainActor public static func renderBBCodeRemotely(_ bbcode: String, accessToken: String? = nil, path: String? = nil) async -> AttributedString {
        // Prefer explicit path argument first
        var endpoints: [URL] = []
        if let p = path, let url = URL(string: p) { endpoints.append(url) }

        // Then respect app setting
        if let endpoint = SettingsService.shared.settings.remoteRenderEndpoint, !endpoint.isEmpty, let url = URL(string: endpoint) {
            endpoints.append(url)
        }

        // Candidate common paths on XenForo servers if no explicit endpoint provided
        if endpoints.isEmpty, let base = URL(string: "https://cities-mods.com") {
            let candidates = ["render-bbcode", "render", "utilities/render-bbcode"]
            for c in candidates { endpoints.append(base.appendingPathComponent(c)) }
        }

        for url in endpoints {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            let body = ["bbcode": bbcode]
            if let data = try? JSONSerialization.data(withJSONObject: body, options: []) { req.httpBody = data }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let html = decoded["html"] as? String ?? decoded["rendered"] as? String ?? decoded["output"] as? String {
                        // Convert HTML to AttributedString via init(html:)
                        if let data = html.data(using: .utf8) {
                            #if os(macOS)
                            if let ns = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                                return AttributedString(ns)
                            }
                            #else
                            if let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                                return AttributedString(attr)
                            }
                            #endif
                        }
                    }
                }
            } catch {
                // try next endpoint
                continue
            }
        }

        // Fallback to local renderer
        return renderBBCodeLocally(bbcode)
    }

    /// Local fallback renderer that uses the built-in BBCode -> AttributedString conversion.
    @MainActor public static func renderBBCodeLocally(_ bbcode: String) -> AttributedString {
        attributedString(from: bbcode)
    }
}

