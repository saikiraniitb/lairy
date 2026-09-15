// AppIdentifying.swift
// OpenClip
//
// Represents external application identity (bundle identifier and localized name).
import Foundation

public struct AppIdentity: Sendable, Equatable, Hashable {
    public let bundleIdentifier: String?
    public let localizedName: String?
    /// The source process's PID at the moment identity was captured — used to guard an early
    /// `SourceContextSnapshot` against being consumed by a different app instance/selection than
    /// the one it was resolved for (see `SourceContextSnapshotValidator`). Not persisted.
    public let processIdentifier: pid_t?

    public init(bundleIdentifier: String? = nil, localizedName: String? = nil, processIdentifier: pid_t? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
    }
}

