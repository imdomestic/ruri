import Foundation
import Darwin
import RuriLocalization

public struct ChorusServerCleanupPlan: Codable, Sendable {
    public let zones: [String]
    private let canonicalDirectory: String
    private let directoryDevice: Int64
    private let directoryInode: UInt64

    package init(zones: Set<String>, directory: URL) throws {
        self.zones = zones.sorted()
        canonicalDirectory = directory.standardizedFileURL.resolvingSymlinksInPath().path
        var info = stat()
        guard lstat(canonicalDirectory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw RuriError.message(Messages.Servers.listChanged)
        }
        directoryDevice = Int64(info.st_dev); directoryInode = UInt64(info.st_ino)
    }

    private func validateDirectory(_ directory: URL) throws {
        var info = stat()
        guard directory.standardizedFileURL.resolvingSymlinksInPath().path == canonicalDirectory,
              lstat(canonicalDirectory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              Int64(info.st_dev) == directoryDevice, UInt64(info.st_ino) == directoryInode else {
            throw RuriError.message(Messages.CoreRepositoryInstanceMover.cleanupDirectoryIdentityChanged)
        }
    }

    package static func normalizedZones(_ values: [String]) throws -> Set<String> {
        try Set(values.map { try ServerAddress($0).host })
    }

    package static func contains(_ address: ServerAddress, zones: Set<String>) -> Bool {
        zones.contains { address.host == $0 || address.host.hasSuffix("." + $0) }
    }

    // 调用方持有实例运行租约；所有路径都限制在已核对的游戏目录。
    @discardableResult package func clean(directory: URL) throws -> Int {
        try validateDirectory(directory)
        let zones = try Self.normalizedZones(zones)
        let file = try SessionFileSystem.safePath("servers.dat", within: directory)
        guard FileManager.default.fileExists(atPath: file.path) else { return 0 }
        let original = try SessionFileSystem.readBounded(file, limit: 8 * 1024 * 1024)
        var document = try NBTReader.serverDocument(original)
        let retained = document.entries.filter { fields in
            guard fields.first(where: { $0.name == "hidden" })?.value.integer.map({ $0 != 0 }) == true,
                  let host = fields.first(where: { $0.name == "ip" })?.value.string,
                  let address = try? ServerAddress(host) else { return true }
            return !Self.contains(address, zones: zones)
        }
        let removed = document.entries.count - retained.count
        guard removed > 0 else { return 0 }
        document.entries = retained
        let updated = try document.encoded()
        guard try SessionFileSystem.readBounded(file, limit: 8 * 1024 * 1024) == original else {
            throw RuriError.message(Messages.Servers.listChanged)
        }
        let backup = try SessionFileSystem.safePath("servers.dat.ruri-backup", within: directory)
        try validateDirectory(directory)
        try original.write(to: backup, options: .atomic)
        try validateDirectory(directory)
        guard try SessionFileSystem.safePath("servers.dat", within: directory).path == file.path,
              try SessionFileSystem.readBounded(file, limit: 8 * 1024 * 1024) == original else {
            throw RuriError.message(Messages.Servers.listChanged)
        }
        try updated.write(to: file, options: .atomic)
        return removed
    }
}
