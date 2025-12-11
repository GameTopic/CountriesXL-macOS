// DownloadManager+ObservableObject.swift
// Removed ObservableObject conformance from DownloadManager.
//
// Rationale:
// DownloadManager is an actor. Making it conform to ObservableObject encourages
// using @ObservedObject/@StateObject and dynamic member lookup ($manager.something),
// which is incompatible with actors and leads to errors like:
// "Referencing subscript 'subscript(dynamicMember:)' requires wrapper 'ObservedObject<DownloadManager>.Wrapper'".
//
// The UI should interact with DownloadManager via async/await (e.g., polling or
// explicit method calls), which is already how DownloadsView works.
// For SwiftUI observation needs, use DownloadManagerV2, which is a proper
// @MainActor ObservableObject with @Published state.
