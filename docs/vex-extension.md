# Vex extension

## 中文

`RuriVex` 提供 Vex 协议、会话、SSE、房间准备与 MRPack 同步；`RuriVexUI` 提供设置、房间与 Git 页面；`RuriVexCLI` 提供 `vex` 命令族。宿主在 `RuriFeatureRegistration` 中为扩展创建上下文并集中注册。通用接口见 [扩展开发说明](extensions.md)。

### 构建

`RURI_ENABLE_VEX=1` 编译 Vex，`RURI_ENABLE_VEX=0` 关闭组件。此分支默认编译组件；运行时设置默认关闭。

```sh
RURI_ENABLE_VEX=1 scripts/build-app.sh debug --build-system swiftbuild
RURI_ENABLE_VEX=0 scripts/build-app.sh debug --build-system swiftbuild
RURI_ENABLE_VEX=1 scripts/swift-build.sh test --build-system swiftbuild --no-parallel
RURI_ENABLE_VEX=0 scripts/swift-build.sh test --build-system swiftbuild --no-parallel
```

需要指定 Xcode 时，设置 `DEVELOPER_DIR`。贡献者签名使用上游的 `RURI_SIGN_IDENTITY`，值为本机代码签名证书的 SHA-1 指纹。

构建入口使用 `--force-resolved-versions` 保留 `Package.resolved` 中全部组件的固定版本。两种组件组合分别使用 `RURI_BUILD_DIR` 下的 `with-vex` 与 `without-vex`，打包只读取对应目录的产物。修改依赖时，显式运行启用组件的 `swift package resolve` 并审阅锁定文件。

直接调用 SwiftPM 构建或测试时，同样传入 `--force-resolved-versions`。SwiftPM 可以下载锁定文件中当前依赖图没有使用的仓库；关闭组件的依赖图和应用产物不包含 EventSource。

Nix 导出 `ruri-launcher`（启用组件）与 `ruri-without-experiments`（关闭组件），两者均保留上游的包管理器集成。Nix 只在构建副本中筛选锁定文件，关闭组件时删除 EventSource pin。应用的 `ruri://` URL scheme 仅随启用组件的构建注册。

### 设置与凭据

启用命令为：

```sh
ruri config set experimental.vex.enabled true --scope app
```

Vex 设置通过宿主上下文保存。关闭组件的应用保存其他设置时，仍保留 Vex 的不透明设置数据。

每台服务器的会话保存在 `dev.ruri.launcher.ext.vex`，账号名称为规范化的服务器 URL。宿主创建同时信任应用与 `Contents/Helpers/ruri-cli`、包含 Delete 授权的 Keychain 访问对象。正式命令首次读取旧服务 `dev.ruri.launcher.vex.api` 中的会话时，按读取、写入新服务、删除旧条目的顺序迁移；已有新条目时使用新条目，并清理同一服务器的旧条目。需要读取会话的查询命令也可能执行迁移，其 schema 的 `sideEffects` 包含 `credentials`。

CLI 的 `help vex`、`schema vex --full` 和补全使用相同的命令声明。GitHub 登录的必要交互提示在文本与 JSON 模式下写入 stderr，NDJSON 模式输出结构化事件；`--quiet` 仍显示完成认证所需的提示。

Vex 登录、添加服务器与预览表单允许通过应用菜单退出。退出、禁用组件或关闭所属表单会取消认证操作，取消后的任务不能保存凭据、设置或更新后续表单。macOS 15.4 起使用 SwiftUI 的 `presentationPreventsAppTermination(false)`；macOS 14 至 15.3 通过局部 AppKit 视图绑定所属窗口，最后一个绑定移除时恢复窗口原值。预览中的内层登录表单与外层预览分别设置各自窗口。

### CLI 预览与准备

`--dry-run` 预览命令不更改用户数据。需要认证的预览优先读取当前 Keychain 会话，缺少当前条目时读取旧条目；读取过程不写入、删除或缓存会话。schema 的 `sideEffects` 描述正式执行可能产生的副作用，预览按下表执行。

| 命令 | 预览检查 |
| --- | --- |
| `servers add/remove/default`、`login`、`logout` | 检查本地参数与服务器选择；不请求登录、退出或修改设置。 |
| `refresh`、`build`、`create` | 读取服务器的项目列表，检查项目选择与命令参数。 |
| `start` | 读取所选房间。 |
| `launch`、`start --launch` | 读取房间与构建，检查已有实例、manifest、模组摘要与 Java，生成启动计划。缺少已准备实例或构建不匹配时报告错误。 |

启动预览不准备实例、不下载文件、不获取房间租约，也不启动房间或游戏。Java 检查会执行本机 Java 版本查询进程，查询输出使用临时文件并在读取后删除。计划中的 `authenticationRequired` 表示本地没有账户记录；预览不刷新游戏账户凭据。

`prepare` 执行真实准备，不提供 `--dry-run`：它可以重新打开或启动房间、管理租约、订阅 SSE，并下载与同步 MRPack，最后返回启动计划。`prepare` 不启动游戏。

联网测试要求显式设置 `VEX_IT_URL` 及各测试所需的参数。没有该变量时，真实服务验收测试跳过。

## English

`RuriVex` implements the protocol, sessions, SSE, room preparation and MRPack synchronization. `RuriVexUI` contributes settings, rooms and Git views. `RuriVexCLI` contributes the `vex` command family. `RuriFeatureRegistration` creates the extension context and registers all contributions. See [the extension guide](extensions.md) for host capabilities.

### Building

Set `RURI_ENABLE_VEX=1` to include the component or `RURI_ENABLE_VEX=0` to omit it. This branch includes the component by default; its runtime setting defaults to off. Use the build and test commands shown above. Select Xcode through `DEVELOPER_DIR` and use upstream's `RURI_SIGN_IDENTITY` for contributor signing.

The build entry point passes `--force-resolved-versions` to preserve the complete lock file. Separate `with-vex` and `without-vex` directories under `RURI_BUILD_DIR` keep each component configuration's binaries and resources together. Explicit dependency updates use `swift package resolve` with the component enabled and require reviewing the lock file.

Pass `--force-resolved-versions` when invoking SwiftPM build or test directly. SwiftPM may fetch pinned repositories that the selected dependency graph does not use. EventSource is absent from the disabled dependency graph and application products.

Nix exports `ruri-launcher` and `ruri-without-experiments`, both retaining upstream's package manager integration. It filters pins only in the build copy, removing EventSource for the disabled package. Only enabled packages register the `ruri://` URL scheme.

### Settings and credentials

Enable the extension with `ruri config set experimental.vex.enabled true --scope app`. Settings are accessed through the host context and survive saving settings from a build that omits Vex.

Sessions use Keychain service `dev.ruri.launcher.ext.vex`, with the canonical server URL as the account. The host trusts both the app and bundled CLI and grants Delete authorization. Normal commands migrate a session from legacy service `dev.ruri.launcher.vex.api` by reading the old item, writing the new one, then deleting the old item. An existing current item takes precedence, and any legacy item for that server is removed. Authenticated queries can also perform this migration, so their schema includes `credentials` in `sideEffects`.

Help, schemas and completion share the command declarations. Required login interaction is written to stderr for text and JSON output, and emitted as structured events for NDJSON. These prompts remain visible with `--quiet`.

Vex login, server addition and preview sheets allow quitting from the application menu. Quitting, disabling the component or closing the owning form cancels authentication; cancelled tasks cannot save credentials or settings or update a subsequent form. macOS 15.4 and later use SwiftUI's `presentationPreventsAppTermination(false)`. On macOS 14 through 15.3, a local AppKit view binds the containing window and restores its original value when the last binding is removed. A preview's nested login sheet and its outer preview configure their own windows independently.

### CLI previews and preparation

`--dry-run` leaves user data unchanged. Authenticated previews read the current Keychain item, or the legacy item when the current item is absent, without writing, deleting or caching a session. Schema `sideEffects` describe possible effects of normal execution; previews perform the following checks.

| Command | Preview checks |
| --- | --- |
| `servers add/remove/default`, `login`, `logout` | Validate local input and server selection without requesting login or logout or saving settings. |
| `refresh`, `build`, `create` | Read the server's project list and validate project selection and command arguments. |
| `start` | Read the selected room. |
| `launch`, `start --launch` | Read the room and build, inspect the existing instance, manifest, mod digests and Java, and return a launch plan. A missing prepared instance or a mismatched build produces an error. |

Launch previews do not prepare an instance, download files, acquire a room lease, or start a room or game. Java inspection runs local version query processes, using temporary output files that are deleted after reading. The plan's `authenticationRequired` indicates that no local account record exists; previews do not refresh game account credentials.

`prepare` performs real preparation and does not accept `--dry-run`: it can reopen or start a room, manage leases, subscribe to SSE, and download and synchronize an MRPack before returning the launch plan. It does not start a game.

Live integration tests require `VEX_IT_URL` and their test-specific parameters. They skip when the root variable is absent.
