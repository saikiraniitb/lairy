// IntentResource.swift
// Core
//
// First-class resource links (Figma, GitHub, Google Docs, ...) attached to a captured intent.
// URLs are always extracted deterministically from source text by `IntentResourceExtractor` —
// never trusted from a model's output. See `IntentUnderstanding.resourceLabels`.
import Foundation

public enum ResourceType: String, Codable, CaseIterable, Sendable {
    case figma
    case github
    case googleDocs
    case googleDrive
    case jira
    case notion
    case genericURL
}

public struct IntentResource: Codable, Equatable, Sendable {
    public var type: ResourceType
    public var url: String
    public var label: String?

    public init(type: ResourceType, url: String, label: String? = nil) {
        self.type = type
        self.url = url
        self.label = label
    }
}

/// Deterministic, provider-independent URL/resource extraction from raw source text.
public enum IntentResourceExtractor {
    /// Matches http(s) URLs. Trailing sentence punctuation and a closing paren/bracket without a
    /// matching opener are stripped so "review it: https://x.com/a." captures a clean URL.
    private static let urlRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"https?://[^\s<>"']+"#, options: [])
    }()

    /// Extracts every URL from `text`, deduplicated in first-seen order, classified by host.
    public static func extractResources(from text: String) -> [IntentResource] {
        let nsText = text as NSString
        let matches = urlRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        var seen = Set<String>()
        var resources: [IntentResource] = []
        for match in matches {
            let raw = nsText.substring(with: match.range)
            let cleaned = cleanTrailingPunctuation(raw)
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { continue }
            resources.append(IntentResource(type: resourceType(forURLString: cleaned), url: cleaned))
        }
        return resources
    }

    /// Strips punctuation a sentence would trail a URL with, and drops one unmatched closing
    /// bracket/paren (e.g. a URL inside "(see https://x.com/a)").
    private static func cleanTrailingPunctuation(_ url: String) -> String {
        var result = url
        let trimSet = CharacterSet(charactersIn: ".,;:!?\"'")
        while let last = result.unicodeScalars.last, trimSet.contains(last) {
            result.removeLast()
        }
        let opens: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
        if let last = result.last, [")", "]", "}"].contains(last) {
            let opener = opens.first { $0.value == last }?.key
            if let opener, result.filter({ $0 == opener }).count < result.filter({ $0 == last }).count {
                result.removeLast()
            }
        }
        return result
    }

    public static func resourceType(forURLString urlString: String) -> ResourceType {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return .genericURL }
        return resourceType(forHost: host)
    }

    public static func resourceType(forHost host: String) -> ResourceType {
        if host.contains("figma.com") { return .figma }
        if host.contains("github.com") { return .github }
        if host.contains("docs.google.com") { return .googleDocs }
        if host.contains("drive.google.com") { return .googleDrive }
        if host.contains("atlassian.net") || host.contains("jira.com") { return .jira }
        if host.contains("notion.so") || host.contains("notion.site") { return .notion }
        return .genericURL
    }
}
