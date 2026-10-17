import Foundation

public struct VexAPIError: Codable, Equatable, Error, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public let details: [String: String]?
    public var errorDescription: String? { message }
}

public struct VexProject: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let defaultBranch: String?
    public let remote: String?
    public let role: String?
    public let loaders: [String]?
}

public enum VexRoomState: String, Codable, Sendable {
    case stopped, queued, building, starting, ready, stopping, archiving, closed, failed, lost
    public var cancelsJoin: Bool { [.failed, .stopping, .archiving, .closed, .lost].contains(self) }
}

public struct VexRoom: Codable, Identifiable, Equatable, Sendable {
    public let project: String
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
    public var state: VexRoomState
    public let phase: String
    public let label: String
    public let node: String?
    public let players: [Player]
    public let idleSince: String?
    public let seed: String
    public let seedResolved: Seed?
    public let world: String?
    public let lastSnapshot: String?
    public let lastError: VexAPIError?
    public let createdAt: String
    public let updatedAt: String
    public let closedAt: String?
    public struct Player: Codable, Equatable, Sendable { public let name: String; public let uuid: String }
    public struct Seed: Codable, Equatable, Sendable { public let kind: String; public let id: String?; public let rev: String? }
}

public enum VexBuildStatus: String, Codable, Sendable { case queued, building, ready, failed }
public struct VexBuild: Codable, Identifiable, Equatable, Sendable {
    public let project: String
    public let id: String
    public let sha: String
    public let loader: String
    public let status: VexBuildStatus
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
    public let lastError: VexAPIError?
    public struct File: Codable, Equatable, Sendable {
        public let name: String
        public let sha1: String?
        public let sha256: String
        public let sha512: String?
        public let size: Int64
        public let side: String
        public let url: String
        public var isClient: Bool { side == "both" || side == "client" }
    }
}
public struct VexLease: Codable, Equatable, Sendable { public let id: String; public let generation: Int; public let expiresAt: String }
public struct VexStartResult: Codable, Sendable { public let room: VexRoom; public let lease: VexLease }
public struct VexBuildSummary: Codable, Equatable, Sendable {
    public let id: String
    public let status: VexBuildStatus
    public init(id: String, status: VexBuildStatus) { self.id = id; self.status = status }
}
public struct VexBranch: Codable, Identifiable, Equatable, Sendable {
    public let project: String
    public var id: String { name }
    public let name: String
    public let head: String
    public let rooms: [String: String]
    public let builds: [String: VexBuildSummary?]
}
public struct VexCommit: Codable, Identifiable, Equatable, Sendable {
    public let project: String
    public var id: String { sha }
    public let sha: String
    public let parents: [String]
    public let subject: String
    public let author: String
    public let time: String
    public let refs: [String]
    public let builds: [String: VexBuildSummary?]
}
public struct VexUser: Codable, Sendable { public let id: String; public let admin: Bool }
public struct VexMeta: Codable, Sendable { public let zone: String; public let publicBaseURL: String? }
public struct VexNode: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let ready: Bool
    public let rootFreeBytes: Int64?
    public var hasLowDiskSpace: Bool { rootFreeBytes.map { $0 < 20 * 1024 * 1024 * 1024 } == true }
}
public struct VexSync: Codable, Sendable { public let rooms: [VexRoom]; public let builds: [VexBuild] }
public struct VexReady: Codable, Sendable {
    public let project: String
    public let id: String
    public let generation: Int
    public let host: String
    public let port: Int
    public let buildId: String
}
public struct VexFailed: Codable, Sendable { public let project: String; public let id: String; public let generation: Int; public let error: VexAPIError }
