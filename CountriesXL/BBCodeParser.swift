import Foundation
import SwiftUI

// BBCode parser for common XenForo 2.x tags used in resource descriptions.
// Converts BBCode into AttributedString for native text rendering and also exposes
// media/image extraction helpers so the UI can render rich embeds separately.

public enum BBCodeParser {
    public struct HTMLBlock: Identifiable, Hashable {
        public let id = UUID()
        public let html: String
    }

    public struct Embed: Identifiable, Hashable {
        public enum Kind: String, Codable {
            case youtube
            case facebook
            case instagram
            case vimeo
            case dailymotion
            case streamable
            case twitch
            case steam
            case imdb
            case soundcloud
            case spotify
            case directVideo
            case audioFile
            case embed
            case url
            case xenforoMedia
            case unknown
        }

        public let id = UUID()
        public let kind: Kind
        public let identifier: String
        public let provider: String?

        public var url: URL? { URL(string: identifier) }
    }

    @MainActor public static func attributedString(
        from bbcode: String,
        attachmentLookup: [String: URL] = [:],
        baseFont: Font = .body
    ) -> AttributedString {
        let normalized = resolveAttachTags(
            in: stripParseHTMLBlocks(from: normalizeCommonTags(in: bbcode)),
            attachmentLookup: attachmentLookup
        )
        let html = htmlString(from: normalized)

        if let data = html.data(using: .utf8),
           let rendered = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
           ) {
            return AttributedString(rendered)
        }

        return AttributedString(cleanFallbackText(from: normalized))
    }

    public static func extractEmbeds(from bbcode: String, attachmentLookup: [String: URL] = [:]) -> [Embed] {
        let normalized = resolveAttachTags(
            in: stripParseHTMLBlocks(from: normalizeCommonTags(in: bbcode)),
            attachmentLookup: attachmentLookup
        )
        var results: [Embed] = []

        let mediaPattern = #"(?is)\[media(?:=(.*?))?\](.*?)\[/media\]"#
        let mediaMatches = regexMatches(pattern: mediaPattern, in: normalized)
        for match in mediaMatches {
            let ns = normalized as NSString
            let provider = match.string(at: 1, in: ns)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = match.string(at: 2, in: ns)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if let id = Int(content) {
                results.append(Embed(kind: .xenforoMedia, identifier: String(id), provider: provider))
            } else if let embed = embed(from: content, providerHint: provider) {
                results.append(embed)
            } else if !content.isEmpty {
                results.append(Embed(kind: .unknown, identifier: content, provider: provider))
            }
        }

        let videoMatches = regexCaptureAll(pattern: #"(?is)\[video\](.*?)\[/video\]"#, in: normalized)
        for match in videoMatches {
            if let embed = embed(from: match, providerHint: "video") {
                results.append(embed)
            }
        }

        let audioMatches = regexCaptureAll(pattern: #"(?is)\[audio\](.*?)\[/audio\]"#, in: normalized)
        for match in audioMatches {
            if let embed = embed(from: match, providerHint: "audio") {
                results.append(embed)
            }
        }

        let embedMatches = regexCaptureAll(pattern: #"(?is)\[embed\](.*?)\[/embed\]"#, in: normalized)
        for match in embedMatches {
            if let embed = embed(from: match, providerHint: "embed") {
                results.append(embed)
            }
        }

        let bareURLMatches = regexCaptureAll(pattern: #"https?://[^\s\[\]<"]+"#, in: normalized)
        for value in bareURLMatches {
            guard let embed = embed(from: value) else { continue }
            let isDuplicate = results.contains { existing in
                existing.kind == embed.kind && existing.identifier == embed.identifier
            }
            if !isDuplicate {
                results.append(embed)
            }
        }

        return results
    }

    public static func extractImageURLs(from bbcode: String, attachmentLookup: [String: URL] = [:]) -> [URL] {
        let normalized = resolveAttachTags(
            in: stripParseHTMLBlocks(from: normalizeCommonTags(in: bbcode)),
            attachmentLookup: attachmentLookup
        )
        let imageTags = regexCaptureAll(pattern: #"(?is)\[img(?:=[^\]]+)?\](.*?)\[/img\]"#, in: normalized)
        var urls = imageTags.compactMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        let bareImageMatches = regexCaptureAll(
            pattern: #"https?://[^\s\[\]<"]+\.(?:png|jpe?g|gif|webp|bmp|heic|heif)(?:\?[^\s\[\]<"]*)?"#,
            in: normalized
        )
        urls.append(contentsOf: bareImageMatches.compactMap(URL.init(string:)))

        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }

    public static func extractHTMLBlocks(from bbcode: String) -> [HTMLBlock] {
        let normalized = normalizeCommonTags(in: bbcode)
        return regexCaptureAll(pattern: #"(?is)\[parsehtml\](.*?)\[/parsehtml\]"#, in: normalized)
            .map { HTMLBlock(html: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.html.isEmpty }
    }

    public static func stripParseHTMLBlocks(from bbcode: String) -> String {
        regexReplace(pattern: #"(?is)\[parsehtml\].*?\[/parsehtml\]"#, in: bbcode) { _ in "" }
    }

    private static func htmlString(from bbcode: String) -> String {
        var working = escapeHTML(bbcode)

        working = regexReplace(pattern: #"(?is)\[code\](.*?)\[/code\]"#, in: working) { groups in
            "<pre><code>\(groups[safe: 1] ?? "")</code></pre>"
        }
        working = regexReplace(pattern: #"(?is)\[quote=(.*?)\](.*?)\[/quote\]"#, in: working) { groups in
            let author = groups[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let body = groups[safe: 2] ?? ""
            return "<blockquote><strong>\(author)</strong><br>\(body)</blockquote>"
        }
        working = regexReplace(pattern: #"(?is)\[quote\](.*?)\[/quote\]"#, in: working) { groups in
            "<blockquote>\(groups[safe: 1] ?? "")</blockquote>"
        }
        working = regexReplace(pattern: #"(?is)\[list(?:=(1|a|A))?\](.*?)\[/list\]"#, in: working) { groups in
            let style = groups[safe: 1]?.lowercased()
            let body = groups[safe: 2] ?? ""
            let items = regexCaptureAll(pattern: #"(?is)\[\*\](.*?)(?=(\[\*\])|$)"#, in: body)
                .map { "<li>\($0.trimmingCharacters(in: .whitespacesAndNewlines))</li>" }
                .joined()
            let tag = style == "1" || style == "a" ? "ol" : "ul"
            return items.isEmpty ? body : "<\(tag)>\(items)</\(tag)>"
        }
        working = regexReplace(pattern: #"(?is)\[url=(.*?)\](.*?)\[/url\]"#, in: working) { groups in
            let url = groups[safe: 1] ?? ""
            let text = groups[safe: 2] ?? url
            return "<a href=\"\(url)\">\(text)</a>"
        }
        working = regexReplace(pattern: #"(?is)\[url\](.*?)\[/url\]"#, in: working) { groups in
            let url = groups[safe: 1] ?? ""
            return "<a href=\"\(url)\">\(url)</a>"
        }
        working = regexReplace(pattern: #"(?is)\[email=(.*?)\](.*?)\[/email\]"#, in: working) { groups in
            let email = groups[safe: 1] ?? ""
            let text = groups[safe: 2] ?? email
            return "<a href=\"mailto:\(email)\">\(text)</a>"
        }
        working = regexReplace(pattern: #"(?is)\[email\](.*?)\[/email\]"#, in: working) { groups in
            let email = groups[safe: 1] ?? ""
            return "<a href=\"mailto:\(email)\">\(email)</a>"
        }
        working = regexReplace(pattern: #"(?is)\[img(?:=[^\]]+)?\](.*?)\[/img\]"#, in: working) { groups in
            ""
        }
        working = regexReplace(pattern: #"(?is)\[video\](.*?)\[/video\]"#, in: working) { groups in
            let url = groups[safe: 1] ?? ""
            return "<a href=\"\(url)\">\(url)</a>"
        }
        working = regexReplace(pattern: #"(?is)\[audio\](.*?)\[/audio\]"#, in: working) { groups in
            let url = groups[safe: 1] ?? ""
            return "<a href=\"\(url)\">\(url)</a>"
        }
        working = regexReplace(pattern: #"(?is)\[embed\](.*?)\[/embed\]"#, in: working) { groups in
            let url = groups[safe: 1] ?? ""
            return "<a href=\"\(url)\">\(url)</a>"
        }
        working = regexReplace(pattern: #"(?is)\[media(?:=.*?)?\](.*?)\[/media\]"#, in: working) { groups in
            let value = groups[safe: 1] ?? ""
            return "<a href=\"\(value)\">\(value)</a>"
        }
        working = regexReplace(pattern: #"(?is)\[color=(.*?)\]"#, in: working) { groups in
            let color = groups[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "inherit"
            return "<span style=\"color:\(color);\">"
        }
        working = regexReplace(pattern: #"(?is)\[/color\]"#, in: working) { _ in "</span>" }
        working = regexReplace(pattern: #"(?is)\[font=(.*?)\]"#, in: working) { groups in
            let font = sanitizeCSSValue(groups[safe: 1] ?? "-apple-system")
            return "<span style=\"font-family:\(font);\">"
        }
        working = regexReplace(pattern: #"(?is)\[/font\]"#, in: working) { _ in "</span>" }
        working = regexReplace(pattern: #"(?is)\[size=(.*?)\]"#, in: working) { groups in
            let size = cssFontSize(from: groups[safe: 1] ?? "")
            return "<span style=\"font-size:\(size);\">"
        }
        working = regexReplace(pattern: #"(?is)\[/size\]"#, in: working) { _ in "</span>" }
        working = regexReplace(pattern: #"(?is)\[plain\](.*?)\[/plain\]"#, in: working) { groups in
            groups[safe: 1] ?? ""
        }
        working = regexReplace(pattern: #"(?is)\[highlight(?:=(.*?))?\]"#, in: working) { groups in
            let rawColor = groups[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let color = (rawColor?.isEmpty == false ? rawColor : "#fff59d") ?? "#fff59d"
            return "<span style=\"background-color:\(sanitizeCSSValue(color));\">"
        }
        working = regexReplace(pattern: #"(?is)\[/highlight\]"#, in: working) { _ in "</span>" }
        working = regexReplace(pattern: #"(?is)\[indent\]"#, in: working) { _ in "<div style=\"margin-left: 24px;\">" }
        working = regexReplace(pattern: #"(?is)\[/indent\]"#, in: working) { _ in "</div>" }
        working = regexReplace(pattern: #"(?is)\[(left|center|right)\]"#, in: working) { groups in
            let alignment = groups[safe: 1] ?? "left"
            return "<div style=\"text-align:\(alignment);\">"
        }
        working = regexReplace(pattern: #"(?is)\[/(left|center|right)\]"#, in: working) { _ in "</div>" }
        working = regexReplace(pattern: #"(?is)\[hr\]"#, in: working) { _ in "<hr>" }
        working = regexReplace(pattern: #"(?is)\[(b|i|u|s|strike|sub|sup)\]"#, in: working) { groups in
            switch groups[safe: 1]?.lowercased() {
            case "b": return "<strong>"
            case "i": return "<em>"
            case "u": return "<u>"
            case "s", "strike": return "<s>"
            case "sub": return "<sub>"
            case "sup": return "<sup>"
            default: return ""
            }
        }
        working = regexReplace(pattern: #"(?is)\[/(b|i|u|s|strike|sub|sup)\]"#, in: working) { groups in
            switch groups[safe: 1]?.lowercased() {
            case "b": return "</strong>"
            case "i": return "</em>"
            case "u": return "</u>"
            case "s", "strike": return "</s>"
            case "sub": return "</sub>"
            case "sup": return "</sup>"
            default: return ""
            }
        }
        working = regexReplace(pattern: #"(?is)\[table(?:=.*?)?\]"#, in: working) { _ in "<table>" }
        working = regexReplace(pattern: #"(?is)\[/table\]"#, in: working) { _ in "</table>" }
        working = regexReplace(pattern: #"(?is)\[tr\]"#, in: working) { _ in "<tr>" }
        working = regexReplace(pattern: #"(?is)\[/tr\]"#, in: working) { _ in "</tr>" }
        working = regexReplace(pattern: #"(?is)\[th(?:=.*?)?\]"#, in: working) { _ in "<th>" }
        working = regexReplace(pattern: #"(?is)\[/th\]"#, in: working) { _ in "</th>" }
        working = regexReplace(pattern: #"(?is)\[td(?:=.*?)?\]"#, in: working) { _ in "<td>" }
        working = regexReplace(pattern: #"(?is)\[/td\]"#, in: working) { _ in "</td>" }
        working = regexReplace(pattern: #"(?is)\[tbody\]"#, in: working) { _ in "<tbody>" }
        working = regexReplace(pattern: #"(?is)\[/tbody\]"#, in: working) { _ in "</tbody>" }
        working = regexReplace(pattern: #"(?is)\[thead\]"#, in: working) { _ in "<thead>" }
        working = regexReplace(pattern: #"(?is)\[/thead\]"#, in: working) { _ in "</thead>" }
        working = regexReplace(pattern: #"(?is)\[tfoot\]"#, in: working) { _ in "<tfoot>" }
        working = regexReplace(pattern: #"(?is)\[/tfoot\]"#, in: working) { _ in "</tfoot>" }
        working = regexReplace(pattern: #"(?is)\[caption\]"#, in: working) { _ in "<caption>" }
        working = regexReplace(pattern: #"(?is)\[/caption\]"#, in: working) { _ in "</caption>" }
        working = regexReplace(pattern: #"(?is)\[style=(.*?)\]"#, in: working) { groups in
            let style = sanitizeCSSValue(groups[safe: 1] ?? "")
            return style.isEmpty ? "" : "<span style=\"\(style)\">"
        }
        working = regexReplace(pattern: #"(?is)\[/style\]"#, in: working) { _ in "</span>" }
        working = regexReplace(pattern: #"(?is)\[icode\](.*?)\[/icode\]"#, in: working) { groups in
            "<code>\(groups[safe: 1] ?? "")</code>"
        }
        working = regexReplace(pattern: #"(?is)\[spoiler(?:=.*?)?\](.*?)\[/spoiler\]"#, in: working) { groups in
            "<details><summary>Spoiler</summary>\(groups[safe: 1] ?? "")</details>"
        }
        working = regexReplace(pattern: #"(?is)\[html\](.*?)\[/html\]"#, in: working) { groups in
            groups[safe: 1] ?? ""
        }
        working = regexReplace(pattern: #"(?is)\[attach[^]]*\](.*?)\[/attach\]"#, in: working) { groups in
            groups[safe: 1] ?? ""
        }
        working = regexReplace(pattern: #"(?is)\[quote=(.*?)\](.*?)\[/quote\]"#, in: working) { groups in
            let author = groups[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let body = groups[safe: 2] ?? ""
            return "<blockquote><strong>\(author)</strong><br>\(body)</blockquote>"
        }
        working = regexReplace(pattern: #"(?is)\[quote\](.*?)\[/quote\]"#, in: working) { groups in
            "<blockquote>\(groups[safe: 1] ?? "")</blockquote>"
        }
        working = regexReplace(pattern: #"(?is)\[noparse\](.*?)\[/noparse\]"#, in: working) { groups in
            groups[safe: 1] ?? ""
        }
        working = regexReplace(pattern: #"(?is)\[user(?:=.*?)?\](.*?)\[/user\]"#, in: working) { groups in
            "@\(groups[safe: 1] ?? "")"
        }
        working = regexReplace(pattern: #"(?is)\[icon(?:=.*?)?\](.*?)\[/icon\]"#, in: working) { groups in
            groups[safe: 1] ?? ""
        }
        working = regexReplace(pattern: #"(?is)\[plain\](.*?)\[/plain\]"#, in: working) { groups in
            groups[safe: 1] ?? ""
        }
        working = regexReplace(pattern: #"(?is)\[block\](.*?)\[/block\]"#, in: working) { groups in
            "<div>\(groups[safe: 1] ?? "")</div>"
        }
        working = regexReplace(pattern: #"(?is)\[(?:align)=(left|center|right)\]"#, in: working) { groups in
            let alignment = groups[safe: 1] ?? "left"
            return "<div style=\"text-align:\(alignment);\">"
        }
        working = regexReplace(pattern: #"(?is)\[/align\]"#, in: working) { _ in "</div>" }
        working = regexReplace(pattern: #"(?is)\[float=(left|right)\]"#, in: working) { groups in
            let side = groups[safe: 1] ?? "left"
            return "<div style=\"float:\(side); margin: 0 12px 12px 0;\">"
        }
        working = regexReplace(pattern: #"(?is)\[/float\]"#, in: working) { _ in "</div>" }
        working = regexReplace(pattern: #"(?is)\[left\]"#, in: working) { _ in "<div style=\"text-align:left;\">" }
        working = regexReplace(pattern: #"(?is)\[/left\]"#, in: working) { _ in "</div>" }
        working = regexReplace(pattern: #"(?is)\[center\]"#, in: working) { _ in "<div style=\"text-align:center;\">" }
        working = regexReplace(pattern: #"(?is)\[/center\]"#, in: working) { _ in "</div>" }
        working = regexReplace(pattern: #"(?is)\[right\]"#, in: working) { _ in "<div style=\"text-align:right;\">" }
        working = regexReplace(pattern: #"(?is)\[/right\]"#, in: working) { _ in "</div>" }
        working = regexReplace(pattern: #"(?is)\[(?:b|i|u|s|strike|sub|sup|font|size|color|style|left|right|center|align|float|highlight|indent|table|tr|th|td|tbody|thead|tfoot|caption|plain|spoiler|block|email|hr|icode|html|noparse|user|icon)\b[^]]*\]"#, in: working) { match in
            match[0]
        }
        working = regexReplace(pattern: #"(?is)\[/(?:b|i|u|s|strike|sub|sup|font|size|color|style|left|right|center|align|float|highlight|indent|table|tr|th|td|tbody|thead|tfoot|caption|plain|spoiler|block|email|icode|html|noparse|user|icon)\]"#, in: working) { match in
            match[0]
        }
        working = regexReplace(pattern: #"(?is)\[attach[^\]]*\].*?\[/attach\]"#, in: working) { _ in "" }
        working = regexReplace(pattern: #"BB_[A-Z0-9_]+"#, in: working) { _ in "" }
        working = regexReplace(pattern: #"(?is)\[[a-z*]+(?:=[^\]]+)?\]"#, in: working) { _ in "" }
        working = regexReplace(pattern: #"(?is)\[/[a-z*]+\]"#, in: working) { _ in "" }
        working = working.replacingOccurrences(of: "__", with: "")
        working = working.replacingOccurrences(of: "\r\n", with: "\n")
        working = working.replacingOccurrences(of: "\n", with: "<br>")

        return """
        <!doctype html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    color: #1f1f1f;
                    font: -apple-system-body;
                    line-height: 1.45;
                }
                a {
                    color: #2563eb;
                    text-decoration: none;
                }
                blockquote {
                    margin: 12px 0;
                    padding: 10px 14px;
                    border-left: 3px solid rgba(37, 99, 235, 0.35);
                    background: rgba(37, 99, 235, 0.06);
                }
                pre {
                    margin: 12px 0;
                    padding: 12px;
                    white-space: pre-wrap;
                    border-radius: 10px;
                    background: rgba(15, 23, 42, 0.06);
                    font: 12px Menlo, Monaco, monospace;
                }
                ul, ol {
                    margin: 10px 0 10px 20px;
                    padding: 0;
                }
                table {
                    width: 100%;
                    margin: 12px 0;
                    border-collapse: collapse;
                    border-spacing: 0;
                    overflow: hidden;
                    border-radius: 10px;
                }
                th, td {
                    padding: 8px 10px;
                    border: 1px solid rgba(15, 23, 42, 0.10);
                    vertical-align: top;
                }
                th {
                    text-align: left;
                    background: rgba(15, 23, 42, 0.05);
                    font-weight: 600;
                }
                hr {
                    margin: 14px 0;
                    border: 0;
                    border-top: 1px solid rgba(15, 23, 42, 0.12);
                }
                details {
                    margin: 12px 0;
                    padding: 10px 12px;
                    border-radius: 10px;
                    background: rgba(15, 23, 42, 0.05);
                }
                code {
                    font: 12px Menlo, Monaco, monospace;
                    background: rgba(15, 23, 42, 0.06);
                    padding: 1px 4px;
                    border-radius: 4px;
                }
            </style>
        </head>
        <body>\(working)</body>
        </html>
        """
    }

    private static func cleanFallbackText(from bbcode: String) -> String {
        var working = bbcode
        working = regexReplace(pattern: #"(?is)\[attach[^\]]*\].*?\[/attach\]"#, in: working) { _ in "" }
        working = regexReplace(pattern: #"(?is)\[(?:/?)(?:[a-z*]+)(?:=[^\]]+)?\]"#, in: working) { _ in "" }
        working = regexReplace(pattern: #"BB_[A-Z0-9_]+"#, in: working) { _ in "" }
        return working.replacingOccurrences(of: "__", with: "")
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func sanitizeCSSValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cssFontSize(from sizeValue: String) -> String {
        let trimmed = sizeValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let namedSizes: [String: String] = [
            "xx-small": "10px",
            "x-small": "11px",
            "small": "12px",
            "medium": "14px",
            "large": "18px",
            "x-large": "22px",
            "xx-large": "28px"
        ]

        if let named = namedSizes[trimmed] {
            return named
        }
        if let numeric = Double(trimmed) {
            let mapped: [Int: Int] = [1: 10, 2: 12, 3: 14, 4: 16, 5: 20, 6: 24, 7: 30]
            if let legacy = mapped[Int(numeric)] {
                return "\(legacy)px"
            }
            return "\(Int(numeric))px"
        }
        if trimmed.hasSuffix("px") || trimmed.hasSuffix("pt") || trimmed.hasSuffix("em") || trimmed.hasSuffix("%") {
            return sanitizeCSSValue(trimmed)
        }
        return "14px"
    }

    private static func embed(from value: String, providerHint: String? = nil) -> Embed? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let hint = providerHint?.lowercased(), !hint.isEmpty, let hinted = embedFromProviderHint(hint, value: trimmed) {
            return hinted
        }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return nil
        }

        if host.contains("youtube.com") || host.contains("youtu.be") {
            if let videoID = youtubeID(from: url) {
                return Embed(kind: .youtube, identifier: videoID, provider: "youtube")
            }
        }
        if host.contains("facebook.com") || host.contains("fb.watch") {
            return Embed(kind: .facebook, identifier: trimmed, provider: "facebook")
        }
        if host.contains("instagram.com") {
            return Embed(kind: .instagram, identifier: trimmed, provider: "instagram")
        }
        if host.contains("store.steampowered.com") || host == "steamcommunity.com" {
            return Embed(kind: .steam, identifier: trimmed, provider: "steam")
        }
        if host.contains("imdb.com") {
            return Embed(kind: .imdb, identifier: trimmed, provider: "imdb")
        }
        if host.contains("vimeo.com") {
            return Embed(kind: .vimeo, identifier: trimmed, provider: "vimeo")
        }
        if host.contains("dailymotion.com") || host.contains("dai.ly") {
            return Embed(kind: .dailymotion, identifier: trimmed, provider: "dailymotion")
        }
        if host.contains("streamable.com") {
            return Embed(kind: .streamable, identifier: trimmed, provider: "streamable")
        }
        if host.contains("twitch.tv") {
            return Embed(kind: .twitch, identifier: trimmed, provider: "twitch")
        }
        if host.contains("soundcloud.com") || host.contains("snd.sc") {
            return Embed(kind: .soundcloud, identifier: trimmed, provider: "soundcloud")
        }
        if host.contains("spotify.com") || host == "open.spotify.com" {
            return Embed(kind: .spotify, identifier: trimmed, provider: "spotify")
        }
        if isDirectVideoURL(url) {
            return Embed(kind: .directVideo, identifier: trimmed, provider: "video")
        }
        if isDirectAudioURL(url) {
            return Embed(kind: .audioFile, identifier: trimmed, provider: "audio")
        }

        return Embed(kind: .url, identifier: trimmed, provider: providerHint)
    }

    private static func embedFromProviderHint(_ providerHint: String, value: String) -> Embed? {
        switch providerHint {
        case "youtube", "youtu":
            return Embed(kind: .youtube, identifier: value, provider: providerHint)
        case "facebook":
            return value.hasPrefix("http") ? Embed(kind: .facebook, identifier: value, provider: providerHint) : nil
        case "instagram":
            return value.hasPrefix("http") ? Embed(kind: .instagram, identifier: value, provider: providerHint) : nil
        case "steam":
            let identifier = value.hasPrefix("http") ? value : "https://store.steampowered.com/app/\(value)"
            return Embed(kind: .steam, identifier: identifier, provider: providerHint)
        case "imdb":
            let identifier = value.hasPrefix("http") ? value : "https://www.imdb.com/title/\(value)"
            return Embed(kind: .imdb, identifier: identifier, provider: providerHint)
        case "vimeo":
            let identifier = value.hasPrefix("http") ? value : "https://vimeo.com/\(value)"
            return Embed(kind: .vimeo, identifier: identifier, provider: providerHint)
        case "dailymotion":
            let identifier = value.hasPrefix("http") ? value : "https://www.dailymotion.com/video/\(value)"
            return Embed(kind: .dailymotion, identifier: identifier, provider: providerHint)
        case "streamable":
            let identifier = value.hasPrefix("http") ? value : "https://streamable.com/\(value)"
            return Embed(kind: .streamable, identifier: identifier, provider: providerHint)
        case "twitch":
            let identifier = value.hasPrefix("http") ? value : "https://www.twitch.tv/videos/\(value)"
            return Embed(kind: .twitch, identifier: identifier, provider: providerHint)
        case "soundcloud":
            let identifier = value.hasPrefix("http") ? value : "https://soundcloud.com/\(value)"
            return Embed(kind: .soundcloud, identifier: identifier, provider: providerHint)
        case "spotify":
            let identifier = value.hasPrefix("http") ? value : "https://open.spotify.com/\(value)"
            return Embed(kind: .spotify, identifier: identifier, provider: providerHint)
        case "video":
            return value.hasPrefix("http") ? Embed(kind: .directVideo, identifier: value, provider: providerHint) : nil
        case "audio":
            return value.hasPrefix("http") ? Embed(kind: .audioFile, identifier: value, provider: providerHint) : nil
        case "embed":
            return value.hasPrefix("http") ? Embed(kind: .embed, identifier: value, provider: providerHint) : nil
        default:
            return value.hasPrefix("http") ? Embed(kind: .url, identifier: value, provider: providerHint) : nil
        }
    }

    private static func youtubeID(from url: URL) -> String? {
        if url.host?.contains("youtu.be") == true {
            return url.pathComponents.dropFirst().first
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            return components.queryItems?.first(where: { $0.name == "v" })?.value
        }
        return nil
    }

    private static func isDirectVideoURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return [".mp4", ".m4v", ".mov", ".webm", ".m3u8"].contains { path.hasSuffix($0) }
    }

    private static func isDirectAudioURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return [".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg"].contains { path.hasSuffix($0) }
    }

    public static func attachmentIDs(in bbcode: String) -> [String] {
        regexCaptureAll(pattern: #"(?is)\[attach[^\]]*\](\d+)\[/attach\]"#, in: normalizeCommonTags(in: bbcode))
    }

    private static func resolveAttachTags(in bbcode: String, attachmentLookup: [String: URL]) -> String {
        guard !attachmentLookup.isEmpty else { return bbcode }
        return regexReplace(pattern: #"(?is)\[attach([^\]]*)\](\d+)\[/attach\]"#, in: bbcode) { groups in
            let options = groups[safe: 1]?.lowercased() ?? ""
            let identifier = groups[safe: 2] ?? ""
            guard let url = attachmentLookup[identifier] else { return "" }
            if shouldRenderAttachmentAsImage(url: url, options: options) {
                return "[img]\(url.absoluteString)[/img]"
            }
            return "[url=\(url.absoluteString)]Attachment \(identifier)[/url]"
        }
    }

    private static func shouldRenderAttachmentAsImage(url: URL, options: String) -> Bool {
        if isLikelyImageURL(url) || options.contains("full") || options.contains("image") || options.contains("thumbnail") {
            return true
        }

        let path = url.path.lowercased()
        let imageHints = ["/attachments/", "/attachment/", "/image/", "/thumbnail/", "/thumb/"]
        let nonImageExtensions = [".zip", ".rar", ".7z", ".pdf", ".txt", ".doc", ".docx", ".xls", ".xlsx", ".mp3", ".m4a", ".wav", ".mp4", ".mov", ".webm"]
        if nonImageExtensions.contains(where: { path.hasSuffix($0) }) {
            return false
        }
        return imageHints.contains(where: { path.contains($0) })
    }

    private static func isLikelyImageURL(_ url: URL) -> Bool {
        let candidate = "\(url.path)?\(url.query ?? "")".lowercased()
        let imageExtensions = [
            ".png", ".jpg", ".jpeg", ".jpe", ".jfif",
            ".gif", ".webp", ".bmp", ".dib",
            ".heic", ".heif", ".avif",
            ".tif", ".tiff",
            ".svg", ".svgz",
            ".ico", ".icns"
        ]
        return imageExtensions.contains { candidate.contains($0) }
    }

    private static func regexMatches(pattern: String, in text: String) -> [NSTextCheckingResult] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
            let ns = text as NSString
            return regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        } catch {
            return []
        }
    }

    private static func regexReplace(pattern: String, in text: String, transform: ([String]) -> String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
            let ns = text as NSString
            var result = text
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                var groups: [String] = []
                for index in 0 ..< match.numberOfRanges {
                    let range = match.range(at: index)
                    if range.location != NSNotFound {
                        groups.append(ns.substring(with: range))
                    } else {
                        groups.append("")
                    }
                }
                result = (result as NSString).replacingCharacters(in: match.range, with: transform(groups))
            }
            return result
        } catch {
            return text
        }
    }

    private static func regexCaptureAll(pattern: String, in text: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
            let ns = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            return results.compactMap { result in
                guard result.numberOfRanges >= 2 else { return nil }
                let range = result.range(at: 1)
                guard range.location != NSNotFound else { return nil }
                return ns.substring(with: range)
            }
        } catch {
            return []
        }
    }

    private static func normalizeCommonTags(in text: String) -> String {
        let replacements: [String: String] = [
            "[B]": "[b]",
            "[/B]": "[/b]",
            "[I]": "[i]",
            "[/I]": "[/i]",
            "[U]": "[u]",
            "[/U]": "[/u]",
            "[S]": "[s]",
            "[/S]": "[/s]",
            "[STRIKE]": "[strike]",
            "[/STRIKE]": "[/strike]",
            "[LIST]": "[list]",
            "[/LIST]": "[/list]",
            "[*]": "[*]",
            "[CENTER]": "[center]",
            "[/CENTER]": "[/center]",
            "[LEFT]": "[left]",
            "[/LEFT]": "[/left]",
            "[RIGHT]": "[right]",
            "[/RIGHT]": "[/right]",
            "[COLOR=": "[color=",
            "[/COLOR]": "[/color]",
            "[FONT=": "[font=",
            "[/FONT]": "[/font]",
            "[SIZE=": "[size=",
            "[/SIZE]": "[/size]",
            "[URL=": "[url=",
            "[URL]": "[url]",
            "[/URL]": "[/url]",
            "[IMG]": "[img]",
            "[/IMG]": "[/img]",
            "[MEDIA": "[media",
            "[/MEDIA]": "[/media]",
            "[VIDEO]": "[video]",
            "[/VIDEO]": "[/video]",
            "[AUDIO]": "[audio]",
            "[/AUDIO]": "[/audio]",
            "[EMBED]": "[embed]",
            "[/EMBED]": "[/embed]",
            "[EMAIL=": "[email=",
            "[EMAIL]": "[email]",
            "[/EMAIL]": "[/email]",
            "[HIGHLIGHT=": "[highlight=",
            "[HIGHLIGHT]": "[highlight]",
            "[/HIGHLIGHT]": "[/highlight]",
            "[INDENT]": "[indent]",
            "[/INDENT]": "[/indent]",
            "[SUB]": "[sub]",
            "[/SUB]": "[/sub]",
            "[SUP]": "[sup]",
            "[/SUP]": "[/sup]",
            "[HR]": "[hr]",
            "[ICODE]": "[icode]",
            "[/ICODE]": "[/icode]",
            "[STYLE=": "[style=",
            "[/STYLE]": "[/style]",
            "[TABLE]": "[table]",
            "[/TABLE]": "[/table]",
            "[TR]": "[tr]",
            "[/TR]": "[/tr]",
            "[TH]": "[th]",
            "[/TH]": "[/th]",
            "[TD]": "[td]",
            "[/TD]": "[/td]",
            "[TBODY]": "[tbody]",
            "[/TBODY]": "[/tbody]",
            "[THEAD]": "[thead]",
            "[/THEAD]": "[/thead]",
            "[TFOOT]": "[tfoot]",
            "[/TFOOT]": "[/tfoot]",
            "[CAPTION]": "[caption]",
            "[/CAPTION]": "[/caption]",
            "[SPOILER": "[spoiler",
            "[/SPOILER]": "[/spoiler]",
            "[NOPARSE]": "[noparse]",
            "[/NOPARSE]": "[/noparse]",
            "[PLAIN]": "[plain]",
            "[/PLAIN]": "[/plain]",
            "[QUOTE": "[quote",
            "[/QUOTE]": "[/quote]",
            "[ATTACH": "[attach",
            "[/ATTACH]": "[/attach]",
            "[PARSEHTML]": "[parsehtml]",
            "[/PARSEHTML]": "[/parsehtml]"
        ]

        return replacements.reduce(text) { partial, replacement in
            partial.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }
}

extension BBCodeParser {
    @MainActor public static func renderBBCodeRemotely(_ bbcode: String, accessToken: String? = nil, path: String? = nil) async -> AttributedString {
        var endpoints: [URL] = []
        if let p = path, let url = URL(string: p) {
            endpoints.append(url)
        }
        if let endpoint = SettingsService.shared.settings.remoteRenderEndpoint, !endpoint.isEmpty, let url = URL(string: endpoint) {
            endpoints.append(url)
        }
        if endpoints.isEmpty, let base = URL(string: "https://cities-mods.com") {
            let candidates = ["render-bbcode", "render", "utilities/render-bbcode"]
            for candidate in candidates {
                endpoints.append(base.appendingPathComponent(candidate))
            }
        }

        for url in endpoints {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let body = ["bbcode": bbcode]
            if let data = try? JSONSerialization.data(withJSONObject: body, options: []) {
                request.httpBody = data
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else { continue }
                if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let html = decoded["html"] as? String ?? decoded["rendered"] as? String ?? decoded["output"] as? String,
                   let htmlData = html.data(using: .utf8),
                   let rendered = try? NSAttributedString(
                    data: htmlData,
                    options: [.documentType: NSAttributedString.DocumentType.html],
                    documentAttributes: nil
                   ) {
                    return AttributedString(rendered)
                }
            } catch {
                continue
            }
        }

        return renderBBCodeLocally(bbcode)
    }

    @MainActor public static func renderBBCodeLocally(_ bbcode: String) -> AttributedString {
        attributedString(from: bbcode)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension NSTextCheckingResult {
    func string(at index: Int, in string: NSString) -> String? {
        guard numberOfRanges > index else { return nil }
        let range = range(at: index)
        guard range.location != NSNotFound else { return nil }
        return string.substring(with: range)
    }
}
