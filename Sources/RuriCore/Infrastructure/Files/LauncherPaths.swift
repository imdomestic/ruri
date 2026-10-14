import RuriLocalization
import Foundation

public struct LauncherPaths: Codable, Sendable, SessionLocationPaths {
    public let root: URL
    public let directories: [GameDirectory]
    public let instanceDirectories: [UUID: UUID]
    public let newInstanceDirectoryID: UUID
    public let instanceRunDirectories: [UUID: GameRunDirectory]?
    public let instanceCustomDirectories: [UUID: CustomRunDirectory]?
    public let instanceRepositoryVersions: [UUID: String]?
    /// Used only while installing an unpublished repository import.
    package var repositoryImportID: UUID?
    public init(root: URL? = nil, directories: [GameDirectory] = [], instanceDirectories: [UUID: UUID] = [:], newInstanceDirectoryID: UUID = GameDirectory.defaultID, instanceRunDirectories: [UUID: GameRunDirectory]? = nil, instanceCustomDirectories: [UUID: CustomRunDirectory]? = nil, instanceRepositoryVersions: [UUID: String]? = nil) {
        // CHORUS: GUI 与 CLI 使用独立支持目录。
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ruri Chorus", isDirectory: true)
        self.directories = directories; self.instanceDirectories = instanceDirectories; self.newInstanceDirectoryID = newInstanceDirectoryID
        self.instanceRunDirectories = instanceRunDirectories
        self.instanceCustomDirectories = instanceCustomDirectories
        self.instanceRepositoryVersions = instanceRepositoryVersions
    }
    public var libraries: URL { root.appendingPathComponent("libraries") }
    public var assets: URL { root.appendingPathComponent("assets") }
    public var versions: URL { root.appendingPathComponent("versions") }
    public var instances: URL { root.appendingPathComponent("instances") }
    public var runtimes: URL { root.appendingPathComponent("runtimes") }
    public var cache: URL { root.appendingPathComponent("cache") }
    public var state: URL { root.appendingPathComponent("state.json") }
    public func instance(_ id: UUID) -> URL {
        if repositoryImportID == id { return repositoryImportWorkspace(id).appendingPathComponent("metadata") }
        return resolvedInstanceDirectory(id)
    }
    public func versionDirectory(_ id: UUID) -> URL {
        if repositoryImportID == id { return repositoryImportWorkspace(id).appendingPathComponent("version") }
        return resolvedVersionDirectory(id)
    }
    func stagingRepositoryImport(_ instance: GameInstance) -> LauncherPaths {
        var result = including(instance); result.repositoryImportID = instance.id; return result
    }
    func clientJar(_ jarID: String, instance: GameInstance) throws -> URL {
        if repositoryImportID == instance.id, jarID == instance.repositoryVersionID {
            return try Self.safePath(jarID + ".jar", within: versionDirectory(instance.id))
        }
        return try Self.safePath("\(jarID)/\(jarID).jar", within: resources(for: instance).versions)
    }
    public func game(_ id: UUID) -> URL { resolvedGameDirectory(id) }
    public func manifest(_ id: UUID) -> URL {
        if let version = instanceRepositoryVersions?[id] { return versionDirectory(id).appendingPathComponent(version + ".json") }
        return instance(id).appendingPathComponent("version.json")
    }
    public func prepare() throws {
        for url in [root, libraries, assets, versions, instances, runtimes, cache] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    }
    public static func safePath(_ path: String, within root: URL) throws -> URL {
        try SessionFileSystem.safePath(path, within: root)
    }
}
