import Foundation
import RuriCore
import CryptoKit
import RuriLocalization

public enum VexMRPack {
    public static func clientFiles(_ build: VexBuild) throws -> [VexBuild.File] {
        guard build.status == .ready, build.minecraft != nil, build.loaderVersion != nil, build.java != nil else {
            throw RuriError.message(Messages.Vex.buildUnavailable)
        }
        let files = build.files.filter(\.isClient)
        guard Set(files.map(\.name)).count == files.count else { throw RuriError.message(Messages.Vex.invalidResponse) }
        for file in files {
            guard file.name.hasSuffix(".jar"), !file.name.hasPrefix("."),
                  !file.name.contains("/"), !file.name.contains("\\"), !file.name.contains("\0"),
                  file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  file.sha1?.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
                  file.sha512?.range(of: "^[0-9a-f]{128}$", options: .regularExpression) != nil, file.size > 0 else {
                throw RuriError.message(Messages.Vex.invalidResponse)
            }
        }
        return files
    }
    static func fingerprint(_ build: VexBuild) throws -> String {
        guard let value = build.clientFingerprint, value == (try computedFingerprint(build)) else {
            throw RuriError.message(Messages.Vex.invalidResponse)
        }
        return value
    }
    static func computedFingerprint(_ build: VexBuild) throws -> String {
        guard let minecraft = build.minecraft, let version = build.loaderVersion,
              [minecraft, build.loader, version].allSatisfy({ $0.range(of: "^[A-Za-z0-9][A-Za-z0-9._+-]*$", options: .regularExpression) != nil }) else {
            throw RuriError.message(Messages.Vex.invalidResponse)
        }
        let hashes = Set(try clientFiles(build).compactMap(\.sha512)).sorted()
        let encodedHashes = String(decoding: try JSONEncoder().encode(hashes), as: UTF8.self)
        // Vex 契约规定字段顺序；运行时字段已限定为不需要 JSON 转义的 ASCII 字符。
        let canonical = "{\"minecraft\":\"\(minecraft)\",\"loader\":\"\(build.loader)\",\"loaderVersion\":\"\(version)\",\"sha512\":\(encodedHashes)}"
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func digest(_ url: URL) throws -> String {
        try ExperimentalInstanceCapabilities.digest(url)
    }
    static func managed(_ file: VexBuild.File) throws -> ExperimentalManagedFile {
        guard let sha1 = file.sha1, let sha512 = file.sha512 else { throw RuriError.message(Messages.Vex.invalidResponse) }
        return .init(path: "mods/" + file.name, sha1: sha1, sha256: file.sha256, sha512: sha512, size: file.size)
    }
    static func verify(_ url: URL, file: VexBuild.File) throws {
        try ExperimentalInstanceCapabilities.verify(url, expected: managed(file))
    }
    static func validate(_ prepared: PreparedInstanceImport, build: VexBuild, roomID: String, generation: Int) throws {
        guard generation > 0, build.attempt > 0,
              let minecraft = build.minecraft, let loader = LoaderKind(rawValue: build.loader), let version = build.loaderVersion else {
            throw RuriError.message(Messages.Vex.invalidResponse)
        }
        let packVersion = "\(roomID)-g\(generation)-\(build.id)-a\(build.attempt)"
        try ExperimentalInstanceCapabilities.validate(prepared, version: packVersion, minecraft: minecraft, loader: loader,
                                                     loaderVersion: version, files: clientFiles(build).map(managed))
    }
    static func verifyInstalled(_ pack: InstalledModpack, game: URL) throws {
        try ExperimentalInstanceCapabilities.verifyTrackedFiles(pack, game: game)
    }
    // 已存在的 R1 实例只转换记录，后续文件更新全部由上游 ModpackUpdater 执行。
    static func adoptLegacy(instance: GameInstance, paths: LauncherPaths, project: String) throws {
        guard try ModpackRegistry.load(paths: paths, instanceID: instance.id) == nil else { return }
        struct Receipt: Decodable { let project: String; let buildID: String; let files: [VexBuild.File] }
        let game = paths.game(instance.id)
        let receipt = try ExperimentalInstanceCapabilities.readMetadata(game.appendingPathComponent("mods/.vex-managed.json"), limit: 8 * 1024 * 1024) as Receipt
        guard receipt.project == project, Set(receipt.files.map(\.name)).count == receipt.files.count else {
            throw RuriError.message(Messages.Vex.invalidResponse)
        }
        let files = try receipt.files.map { file -> ExperimentalManagedFile in
            guard file.name.hasSuffix(".jar"), !file.name.hasPrefix("."), !file.name.contains("/"), !file.name.contains("\\") else {
                throw RuriError.message(Messages.Vex.invalidResponse)
            }
            return try managed(file)
        }
        try ExperimentalInstanceCapabilities(paths: paths).recordExistingPack(instance: instance, version: receipt.buildID, files: files)
    }
}
