// TemporalPhraseExtractor.swift
// Core
//
// Deterministic, provider-independent scan of raw text for temporal phrases (today, tomorrow,
// weekday names, explicit clock times, explicit calendar dates). Used as independent evidence by
// `IntentGroundingValidator` to decide whether a provider-claimed deadline/time is real or
// hallucinated — never to resolve a phrase to an actual date (see `IntentDeadlineResolver`).
import Foundation

public enum TemporalPhraseExtractor {
    private static let keywordPhrases = [
        "today", "tonight", "tomorrow", "yesterday",
        "next week", "next month", "this week", "this weekend",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "next monday", "next tuesday", "next wednesday", "next thursday", "next friday",
        "next saturday", "next sunday"
    ]

    /// e.g. "5pm", "5 pm", "5:30pm", "17:00"
    private static let clockTimeRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b(\d{1,2}(:\d{2})?\s?(am|pm|AM|PM))\b|\b([01]?\d|2[0-3]):[0-5]\d\b"#,
            options: []
        )
    }()

    /// e.g. "September 21", "Sep 21", "21 September", "2026-09-21", "9/21"
    private static let explicitDateRegex: NSRegularExpression = {
        let months = "January|February|March|April|May|June|July|August|September|October|November|December|" +
            "Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec"
        let pattern = #"\b(("# + months + #")\s+\d{1,2}(st|nd|rd|th)?(,?\s+\d{4})?|\d{1,2}\s+("# + months +
            #")(,?\s+\d{4})?|\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}(/\d{2,4})?)\b"#
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Returns every temporal phrase found verbatim in `text` (original casing/substring
    /// preserved), in first-seen order, deduplicated.
    public static func extractPhrases(from text: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()

        let lower = text.lowercased()
        for phrase in keywordPhrases {
            guard lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b", options: .regularExpression) != nil else { continue }
            if seen.insert(phrase).inserted { found.append(phrase) }
        }

        for regex in [clockTimeRegex, explicitDateRegex] {
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let value = nsText.substring(with: match.range)
                let key = value.lowercased()
                if seen.insert(key).inserted { found.append(value) }
            }
        }

        return found
    }

    /// True when `phrase` is grounded: it appears verbatim (case-insensitive, whitespace-
    /// normalized) in `text`, AND at least one independently-recognized temporal phrase exists
    /// somewhere in `text` at all. A source with zero recognizable temporal evidence can never
    /// ground a claimed deadline/time, even if the exact words happen to substring-match.
    public static func isGrounded(phrase: String, in text: String) -> Bool {
        let evidence = extractPhrases(from: text)
        guard !evidence.isEmpty else { return false }
        return TextGrounding.containsVerbatim(phrase, in: text)
    }
}

/// Shared verbatim-substring grounding check used across grounding rules (temporal phrases,
/// person/company mentions, triggers, ...). Whitespace-normalized, case-insensitive.
public enum TextGrounding {
    public static func containsVerbatim(_ candidate: String, in text: String) -> Bool {
        let normalizedCandidate = normalize(candidate)
        guard !normalizedCandidate.isEmpty else { return false }
        return normalize(text).contains(normalizedCandidate)
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
