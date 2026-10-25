# Extensions

Extensions are optional modules compiled into Ruri. They add pages, settings, commands and pre-launch work to the application and the command line. The extension points are an internal interface of this repository and may change at any time without compatibility guarantees.

### Ground rules

- An extension is code in this repository, linked statically at build time. Ruri loads no plug-ins, dynamic libraries or scripts, and has no interface for installing extensions.
- Extensions are off by default. Users turn one on in the extension's section of the settings page, or with `ruri config set experimental.<id>.enabled true --scope app`. While it is off, the extension shows only its switch on the settings page; its pages are hidden, its command family is absent from help, completion and schemas, and its hooks do not run.
- With no extension compiled in, CLI discovery output is byte-identical to upstream (`Tests/RuriCLITests/ExtensionGoldenTests.swift`). The sidebar, home and settings pages have the same Accessibility text (`Tests/RuriExtensionTests/GUIGoldenTests.swift`).
- When an extension is not compiled into the current build, the host keeps its stored settings unchanged.

### Writing an extension

An extension has three parts, usually in three targets:

| Part | Protocol | Module |
| --- | --- | --- |
| Core hooks | `ExperimentalFeatureHooks` | `RuriCore` |
| Interface | `ExperimentalUIProvider` | `RuriExtensionKit` |
| Command line | `ExperimentalCommandProvider` | `RuriCommandKit` |

Register it in `Sources/RuriFeatureRegistration/CompiledExperimentalFeatures.swift` behind its own build condition:

```swift
#if RURI_EXAMPLE_ENABLED
install("example") { context in
    (ExampleFeature.hooks(context), ExampleUIProvider(context: context), ExampleCLIProvider(context: context))
}
#endif
```

`install` claims the extension's ID (a lowercase letter, then up to 31 letters, digits or hyphens) and creates its `ExperimentalExtensionContext`. An ID can be claimed once per process. The extension reads and writes its own settings and secure storage through this context.

`Package.swift` declares the extension's targets and dependencies only when the extension is on, and `RuriFeatureRegistration` depends on those targets and defines the build condition. A build without the extension then neither compiles, links nor resolves its dependencies.

`Tests/RuriExtensionTests/SampleExtension.swift` implements the contribution interfaces. The tests exercise command discovery, configuration, target resolution, core hooks, UI registration and lifecycle, secure storage, and import exclusions.

### Verifying an empty registration

`ExtensionGoldenTests` compares all 18 discovery outputs against `ExtensionGolden.json`. When checking a different toolchain or build configuration, set `RURI_CLI_GOLDEN_MANIFEST` to a manifest captured from upstream main with that same configuration. A missing or invalid manifest fails the test. Record expected output only from an upstream main build; `RURI_RECORD_GOLDEN=1` writes the selected manifest.

For the sidebar, home and settings pages, set `RURI_GUI_GOLDEN_APP` to the app being checked and run `GUIGoldenTests` with Accessibility access. To update `GUIGolden.json`, point it at a build of upstream main and set `RURI_RECORD_GOLDEN=1`, then run again against the extension branch without the recording flag. The test uses an isolated app copy and data directory.

### Localization

An extension keeps its String Catalogs in `Sources/<Module>/Localization/Resources/*.xcstrings` and declares them in `Package.swift` with `.process("Localization/Resources")`. `scripts/localization.py` checks them together with the host's catalogs and generates `Messages` accessors in `Sources/<Module>/Localization/Generated`; table names must differ from the host's and other extensions'. At registration the extension calls `LocalizationCatalogRegistry.register(table:definitions:bundle:)` for each table, with the `Ruri_<Module>.bundle` that `LocalizationResources.installedBundle(executable:mainResources:name:)` finds. The application's `--localization-check` covers the registered tables as well. Builds without Xcode compile each module's bundle with `scripts/localization.py --compile <bundle>`.

### Contribution points

- **Before launch**: `beforeLaunch(paths, instanceID, settings)` runs after the run directory is prepared and before the launch command is built. An error stops the launch.
- **Server list**: when `hidesServer(server, settings)` returns `true`, the server is left out of the Servers page.
- **Sidebar pages**: each page from `pages(host:)` gets its own section between the main pages and the records; `page(_:host:)` provides its content.
- **Settings**: `settings(host:)` appears after the command line settings, also while the extension is off, to hold its switch.
- **Servers page**: `servers(host:)` appears above the server list.
- **Links**: `open(_:host:)` returns a view, shown in a sheet, for a URL the application was asked to open, or `nil` to leave it.
- **Lifecycle**: `configure(host:)` runs at launch and whenever settings change; `stop()` stops background work before the application quits. UI providers receive these callbacks while disabled too, and must keep network, Keychain and background work inactive until enabled.
- **Command family**: a top-level group with its command descriptions (`CommandSpec`). The family uses the same layered help, global options in any position, target resolution by name or short ID (the parameter `role`), completion, schemas, `--details` and `--color` as the built-in commands. `presenter(_:)` returns the text form by what a result is for (list, detail, change, diagnosis, raw), and `ExperimentalText` offers the same tables, fields and change layout as the built-in commands. `schema(_:)` and `sideEffects(_:)` describe results and side effects. The root help lists the family on its own under `section`.

### Host capabilities

An extension can use:

- Its own settings: `context.configuration(paths)` to read and write, `host.settings(context)` for the value the application currently holds. Settings are an opaque JSON value; the host manages the `enabled` field and may write it alone, so decoding should give other missing fields their defaults.
- Its own secure storage: `context.secureStorage`, under the Keychain service `dev.ruri.launcher.ext.<id>`. Items trust both the application and the bundled `ruri-cli` and carry the Delete authorization, so either one can remove what the other created.
- Account state: `host.accountAvailable`, `host.openAccount()`.
- Instances, Modrinth packs and files: `ExperimentalInstanceCapabilities` (reading instances, setting the Java version, preparing and installing `.mrpack` files, leaving out files the extension manages, verifying files, Quick Play arguments).
- Launches and sessions: `host.beginLaunch`, `host.start`, `host.session`, `host.sessions`, or `ExperimentalLaunchCapabilities`.
- The application's feedback: `host.report(_:)`, `host.reload()`, `host.readOnly`, `host.busy`.
- Required command-line interaction: `output.interaction(type, value)` writes to stderr in text and JSON modes and emits a structured event in NDJSON mode. These prompts remain visible with `--quiet`, and all content passes through secret redaction.

The context and UI host expose:

- Settings and secure storage for the claimed extension ID. Only the host creates contexts, and the secure storage service follows from that ID.
- Account availability and account presentation, without passing Microsoft credentials.
- Application capabilities through `ExperimentalHost`, with `AppModel` remaining internal to the application.

Core hooks and command execution are gated by the enabled setting. UI providers keep only their settings switch visible while disabled. These interfaces define how trusted extensions compiled into the application integrate with the host.
