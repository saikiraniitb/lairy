import Foundation

/// Opt-in build diagnostics. Never logs the original selection or provider response.
public enum IntentCaptureTrace {
    public static func record(stage: String, captureID: UUID, type: IntentType?, sourceContext: IntentSourceContext?) {
        #if DEBUG
        Log.intent.debug("captureID=\(captureID.uuidString, privacy: .public) stage=\(stage, privacy: .public) type=\(type?.rawValue ?? "none", privacy: .public) direction=\(sourceContext?.direction.rawValue ?? "unknown", privacy: .public) conversationTitle=\(sourceContext?.conversationTitle ?? "nil") oneOnOneParticipant=\(sourceContext?.oneOnOneParticipant ?? "nil") sender=\(sourceContext?.sender ?? "nil") source=\(sourceContext?.applicationName ?? "nil")")
        #endif
    }

    public static func record(stage: String, draft: IntentDraft) {
        guard let captureID = draft.captureID else { return }
        record(stage: stage, captureID: captureID, type: draft.type, sourceContext: draft.sourceContext)
        #if DEBUG
        Log.intent.debug("captureID=\(captureID.uuidString, privacy: .public) stage=\(stage, privacy: .public) summary=\(draft.summary) subject=\(draft.subject ?? "nil") waitingFor=\(draft.waitingFor ?? "nil") requestedBy=\(draft.requestedBy ?? "nil") dueAt=\(draft.dueAt?.date.description ?? "nil", privacy: .public) eventAt=\(draft.eventAt?.date.description ?? "nil", privacy: .public) followUpAt=\(draft.followUpAt?.date.description ?? "nil", privacy: .public)")
        #endif
    }
}
