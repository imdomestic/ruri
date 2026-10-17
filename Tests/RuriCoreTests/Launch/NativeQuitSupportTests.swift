import Foundation
import Testing
@testable import RuriCore

struct NativeQuitSupportTests {
    @Test func recognizesGLFWAndSDLButExcludesLegacyLWJGL() throws {
        func manifest(_ names: [String]) throws -> VersionManifest {
            let libraries = try names.map { name in
                try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(["name": name]))
            }
            return VersionManifest(id: "native-quit", libraries: libraries)
        }
        #expect(try LaunchBuilder.supportsNativeQuit(manifest(["org.lwjgl:lwjgl-glfw:3.3.6"])))
        #expect(try LaunchBuilder.supportsNativeQuit(manifest(["org.lwjgl:lwjgl-sdl:3.4.1"])))
        #expect(try !LaunchBuilder.supportsNativeQuit(manifest([])))
        #expect(try !LaunchBuilder.supportsNativeQuit(manifest(["org.lwjgl.lwjgl:lwjgl:2.9.4", "org.lwjgl:lwjgl-sdl:3.4.1"])))
    }
}
