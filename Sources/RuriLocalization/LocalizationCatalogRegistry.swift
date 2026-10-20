import Foundation

public enum LocalizationCatalogRegistry {
    struct Catalog: Sendable { let definitions: [String: MessageDefinition]; let bundle: Bundle? }
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var catalogs: [String: Catalog] = [:]
    }
    private static let storage = Storage()
    public static func register(table: String, definitions: [String: MessageDefinition], bundle: Bundle?) {
        storage.lock.withLock {
            precondition(storage.catalogs[table] == nil)
            storage.catalogs[table] = Catalog(definitions: definitions, bundle: bundle)
        }
    }
    static func catalog(_ table: String) -> Catalog? { storage.lock.withLock { storage.catalogs[table] } }
    static func resourcesAvailable() -> Bool {
        storage.lock.withLock {
            storage.catalogs.allSatisfy { table, catalog in
                guard let bundle = catalog.bundle,
                      let path = bundle.path(forResource: LocalizationContext.baseLanguage, ofType: "lproj"),
                      let localized = Bundle(path: path) else { return false }
                return catalog.definitions.keys.allSatisfy { identity in
                    let key = String(identity.dropFirst(table.count + 1))
                    return localized.localizedString(forKey: key, value: "MISSING", table: table) != "MISSING"
                }
            }
        }
    }
}
