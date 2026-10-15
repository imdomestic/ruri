import Foundation

public struct ChorusAPIError: Codable, Equatable, Error, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public let details: [String: String]?
    public var errorDescription: String? { message }
}

public enum ChorusRoomState: String, Codable, Sendable {
    case stopped, queued, building, starting, ready, stopping, archiving, closed, failed, lost
    public var cancelsJoin: Bool { [.failed, .stopping, .archiving, .closed, .lost].contains(self) }
}

public struct ChorusRoom: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let branch: String?
    public let sha: String
    public let loader: String
    public let buildId: String
    public let generation: Int
    public let behindHead: Bool
    public var host: String
    public var port: Int
    public var state: ChorusRoomState
    public let phase: String
    public let label: String
    public let node: String?
    public let players: [Player]
    public let idleSince: String?
    public let seed: String
    public let seedResolved: Seed?
    public let asset: String?
    public let lastSnapshot: String?
    public let lastError: ChorusAPIError?
    public let createdAt: String
    public let updatedAt: String
    public var closedAt: String? = nil
    public struct Player: Codable, Equatable, Sendable { public let name: String; public let uuid: String }
    public struct Seed: Codable, Equatable, Sendable { public let kind: String; public let id: String?; public let rev: String? }
}

public enum ChorusBuildStatus: String, Codable, Sendable { case queued, building, ready, failed }

public struct ChorusBuild: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let sha: String
    public let loader: String
    public let status: ChorusBuildStatus
    public let attempt: Int
    public let queuedAt: String
    public let startedAt: String?
    public let finishedAt: String?
    public let minecraft: String?
    public let loaderVersion: String?
    public let java: Int?
    public let builtAt: String?
    public let durationSec: Double?
    public let modIds: [String]
    public let files: [File]
    public let log: String
    public let lastError: ChorusAPIError?
    public struct File: Codable, Equatable, Sendable {
        public let name: String
        public let sha256: String
        public let size: Int64
        public let side: String
        public let url: String
        public var isClient: Bool { side == "both" || side == "client" }
    }
}

public struct ChorusLease: Codable, Equatable, Sendable { public let id: String; public let generation: Int; public let expiresAt: String }
public struct ChorusStartResult: Codable, Sendable { public let room: ChorusRoom; public let lease: ChorusLease }
public struct ChorusBuildSummary: Codable, Equatable, Sendable {
    public let id: String
    public let status: ChorusBuildStatus
    public init(id: String, status: ChorusBuildStatus) { self.id = id; self.status = status }
}
public struct ChorusBranch: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let head: String
    public let rooms: [String: String]
    public let builds: [String: ChorusBuildSummary?]
}
public struct ChorusCommit: Codable, Identifiable, Equatable, Sendable {
    public var id: String { sha }
    public let sha: String
    public let parents: [String]
    public let subject: String
    public let author: String
    public let time: String
    public let refs: [String]
    public let builds: [String: ChorusBuildSummary?]
}
public struct ChorusMeta: Codable, Sendable {
    public let minecraft: String
    public let java: Int
    public let zone: String
    public let loaders: [String]
    public let publicBaseURL: String
    public let limits: Limits
    public struct Limits: Codable, Sendable { public let buildConcurrency: Int; public let buildCacheSize: Int; public let maxRunning: [String: Int] }
}
public struct ChorusNode: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let ready: Bool
    public let schedulable: Bool
    public let maxRunning: Int
    public let rooms: [String]
    public let rootFreeBytes: Int64?
    public static let diskWarningThreshold: Int64 = 20 * 1024 * 1024 * 1024
    public var hasLowDiskSpace: Bool {
        name == "encore" && rootFreeBytes.map { $0 < Self.diskWarningThreshold } == true
    }
}
public struct ChorusAsset: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let state: String
    public let latestRev: String
    public let minecraft: String
    public let requires: Requirements
    public let resourcePack: Pack?
    public struct Requirements: Codable, Sendable { public let loaders: [String]; public let chorusMod: Bool; public let namespaces: [String] }
    public struct Pack: Codable, Sendable { public let id: String; public let rev: String }
}

public struct ChorusSync: Codable, Sendable { public let rooms: [ChorusRoom]; public let builds: [ChorusBuild] }
public struct ChorusReady: Codable, Sendable { public let id: String; public let generation: Int; public let host: String; public let port: Int; public let buildId: String }
public struct ChorusFailed: Codable, Sendable { public let id: String; public let generation: Int; public let error: ChorusAPIError }
