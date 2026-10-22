# Extensions · 扩展

[中文](#中文) · [English](#english)

## 中文

扩展是编译进 Ruri 的可选模块，向应用和命令行添加页面、设置、命令和启动前的处理。扩展点是仓库内部接口，随时可能调整，不承诺兼容。

### 基本规则

- 扩展只能是本仓库中、编译时静态链接的代码。Ruri 不加载插件、动态库或脚本，也没有安装扩展的界面。
- 扩展默认关闭。用户在设置页中该扩展的区块里打开，或者执行 `ruri config set experimental.<id>.enabled true --scope app`。关闭时，扩展只在设置页显示自己的开关；页面不显示，命令族不出现在帮助、补全和 schema 中，钩子不运行。
- 没有编译任何扩展时，应用的侧栏、首页、设置页，以及命令行的 `help`、`help --all`、`schema`、`schema --full` 与没有扩展支持的 Ruri 逐字节相同（`Tests/RuriCLITests/ExtensionGoldenTests.swift`）。
- 扩展未编译进当前构建时，它保存在设置中的数据由宿主原样保留。

### 编写一个扩展

一个扩展由三部分组成，通常分别放在三个 target 中：

| 部分 | 协议 | 所在模块 |
| --- | --- | --- |
| 核心钩子 | `ExperimentalFeatureHooks` | `RuriCore` |
| 界面 | `ExperimentalUIProvider` | `RuriExtensionKit` |
| 命令行 | `ExperimentalCommandProvider` | `RuriCommandKit` |

在 `Sources/RuriFeatureRegistration/CompiledExperimentalFeatures.swift` 中，以单独的编译条件注册：

```swift
#if RURI_EXAMPLE_ENABLED
install("example") { context in
    (ExampleFeature.hooks(context), ExampleUIProvider(context: context), ExampleCLIProvider(context: context))
}
#endif
```

`install` 为扩展领取 ID（小写字母开头，最多 32 个字母、数字或连字符）并创建它的 `ExperimentalExtensionContext`。同一个 ID 在一个进程中只能领取一次。扩展通过这个上下文读写自己的设置和安全存储。

`Package.swift` 只在开启扩展时声明它的 target 与依赖，`RuriFeatureRegistration` 依赖这些 target 并定义编译条件。这样关闭扩展的构建不会编译、链接或解析它的依赖。

`Tests/RuriExtensionTests/SampleExtension.swift` 是一个完整的示例，覆盖下面列出的全部贡献点和宿主能力。

### 本地化

扩展把自己的 String Catalog 放在 `Sources/<模块>/Localization/Resources/*.xcstrings`，在 `Package.swift` 中以 `.process("Localization/Resources")` 声明为资源。`scripts/localization.py` 与宿主的目录一起校验这些文件，并在 `Sources/<模块>/Localization/Generated` 生成扩展 `Messages` 的访问器；表名不能与宿主或其他扩展重复。扩展在注册时为每张表调用 `LocalizationCatalogRegistry.register(table:definitions:bundle:)`，bundle 取 `LocalizationResources.installedBundle(executable:mainResources:name:)` 找到的 `Ruri_<模块>.bundle`。应用的 `--localization-check` 同时检查已注册的表。不用 Xcode 构建时，用 `scripts/localization.py --compile <bundle>` 为每个模块的 bundle 编译目录。

### 贡献点

- **启动前**：`beforeLaunch(paths, instanceID, settings)` 在准备好运行目录之后、生成启动命令之前运行，抛出错误会中止启动。
- **服务器列表**：`hidesServer(server, settings)` 返回 `true` 时，该服务器不在服务器页面中显示。
- **侧栏页面**：`pages(host:)` 返回的每个页面在主页面与记录之间单独成为一节；`page(_:host:)` 提供页面内容。
- **设置**：`settings(host:)` 显示在命令行设置之后。扩展关闭时也会显示，用来放置扩展的开关。
- **服务器页面**：`servers(host:)` 显示在服务器列表之上。
- **链接**：`open(_:host:)` 为应用收到的 URL 返回一个在表单中显示的视图，不处理时返回 `nil`。
- **生命周期**：`configure(host:)` 在启动时和设置变化时运行；`stop()` 在退出前停止后台工作。
- **命令族**：一个顶层命令组及其命令说明（`CommandSpec`）。命令族使用与内置命令相同的分层帮助、任意位置的全局选项、按名称或短 ID 解析目标（参数的 `role`）、补全、schema、`--details` 与 `--color`。`presenter(_:)` 按结果用途（列表、详情、变更、诊断、原样）返回文本格式，`ExperimentalText` 提供与内置命令相同的表格、字段与变更布局；`schema(_:)` 与 `sideEffects(_:)` 描述结果与副作用。命令族在帮助首页以 `section` 为标题单独列出。

### 宿主能力

扩展可以使用：

- 自己的设置：`context.configuration(paths)` 读写，`host.settings(context)` 读取应用当前持有的值。设置是不透明的 JSON 值，`enabled` 字段由宿主管理；宿主可能只写入 `enabled`，解码时其他字段缺失应取默认值。
- 自己的安全存储：`context.secureStorage`，钥匙串服务名为 `dev.ruri.launcher.ext.<id>`。条目同时信任主程序与随附的 `ruri-cli`，并带有删除授权，任一方创建的条目另一方都可以删除。
- 账号状态：`host.accountAvailable`、`host.openAccount()`。
- 实例、Modrinth 包与文件：`ExperimentalInstanceCapabilities`（读取实例、设置 Java 版本、准备与安装 `.mrpack`、排除由扩展管理的文件、校验文件、Quick Play 参数）。
- 启动与会话：`host.beginLaunch`、`host.start`、`host.session`、`host.sessions`，或 `ExperimentalLaunchCapabilities`。
- 应用的提示：`host.report(_:)`、`host.reload()`、`host.readOnly`、`host.busy`。

扩展拿不到：

- 其他扩展的设置与安全存储。上下文只由宿主创建，安全存储的服务名由扩展 ID 决定。
- Microsoft 账号凭据、令牌和其他钥匙串服务。
- `AppModel` 与应用内部状态；界面只能经 `ExperimentalHost` 访问。
- 在没有被打开时运行任何功能：关闭的扩展只显示设置页中的开关，不显示页面，不加入命令，不运行钩子。

## English

Extensions are optional modules compiled into Ruri. They add pages, settings, commands and pre-launch work to the application and the command line. The extension points are an internal interface of this repository and may change at any time without compatibility guarantees.

### Ground rules

- An extension is code in this repository, linked statically at build time. Ruri loads no plug-ins, dynamic libraries or scripts, and has no interface for installing extensions.
- Extensions are off by default. Users turn one on in the extension's section of the settings page, or with `ruri config set experimental.<id>.enabled true --scope app`. While it is off, the extension shows only its switch on the settings page; its pages are hidden, its command family is absent from help, completion and schemas, and its hooks do not run.
- With no extension compiled in, the sidebar, home page and settings page of the application, and `help`, `help --all`, `schema` and `schema --full` on the command line, are byte-for-byte those of Ruri without extension support (`Tests/RuriCLITests/ExtensionGoldenTests.swift`).
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

`Tests/RuriExtensionTests/SampleExtension.swift` is a complete example that uses every contribution point and host capability listed below.

### Localization

An extension keeps its String Catalogs in `Sources/<Module>/Localization/Resources/*.xcstrings` and declares them in `Package.swift` with `.process("Localization/Resources")`. `scripts/localization.py` checks them together with the host's catalogs and generates `Messages` accessors in `Sources/<Module>/Localization/Generated`; table names must differ from the host's and other extensions'. At registration the extension calls `LocalizationCatalogRegistry.register(table:definitions:bundle:)` for each table, with the `Ruri_<Module>.bundle` that `LocalizationResources.installedBundle(executable:mainResources:name:)` finds. The application's `--localization-check` covers the registered tables as well. Builds without Xcode compile each module's bundle with `scripts/localization.py --compile <bundle>`.

### Contribution points

- **Before launch**: `beforeLaunch(paths, instanceID, settings)` runs after the run directory is prepared and before the launch command is built. An error stops the launch.
- **Server list**: when `hidesServer(server, settings)` returns `true`, the server is left out of the Servers page.
- **Sidebar pages**: each page from `pages(host:)` gets its own section between the main pages and the records; `page(_:host:)` provides its content.
- **Settings**: `settings(host:)` appears after the command line settings, also while the extension is off, to hold its switch.
- **Servers page**: `servers(host:)` appears above the server list.
- **Links**: `open(_:host:)` returns a view, shown in a sheet, for a URL the application was asked to open, or `nil` to leave it.
- **Lifecycle**: `configure(host:)` runs at launch and whenever settings change; `stop()` stops background work before the application quits.
- **Command family**: a top-level group with its command descriptions (`CommandSpec`). The family uses the same layered help, global options in any position, target resolution by name or short ID (the parameter `role`), completion, schemas, `--details` and `--color` as the built-in commands. `presenter(_:)` returns the text form by what a result is for (list, detail, change, diagnosis, raw), and `ExperimentalText` offers the same tables, fields and change layout as the built-in commands. `schema(_:)` and `sideEffects(_:)` describe results and side effects. The root help lists the family on its own under `section`.

### Host capabilities

An extension can use:

- Its own settings: `context.configuration(paths)` to read and write, `host.settings(context)` for the value the application currently holds. Settings are an opaque JSON value; the host manages the `enabled` field and may write it alone, so decoding should give other missing fields their defaults.
- Its own secure storage: `context.secureStorage`, under the Keychain service `dev.ruri.launcher.ext.<id>`. Items trust both the application and the bundled `ruri-cli` and carry the Delete authorization, so either one can remove what the other created.
- Account state: `host.accountAvailable`, `host.openAccount()`.
- Instances, Modrinth packs and files: `ExperimentalInstanceCapabilities` (reading instances, setting the Java version, preparing and installing `.mrpack` files, leaving out files the extension manages, verifying files, Quick Play arguments).
- Launches and sessions: `host.beginLaunch`, `host.start`, `host.session`, `host.sessions`, or `ExperimentalLaunchCapabilities`.
- The application's feedback: `host.report(_:)`, `host.reload()`, `host.readOnly`, `host.busy`.

An extension cannot reach:

- Other extensions' settings and secure storage. Only the host creates contexts, and the secure storage service follows from the extension's ID.
- Microsoft account credentials, tokens or other Keychain services.
- `AppModel` and the application's internal state; views go through `ExperimentalHost` only.
- Any of its functions while it is off: a disabled extension shows only its switch on the settings page, no pages, no commands, and runs no hooks.
