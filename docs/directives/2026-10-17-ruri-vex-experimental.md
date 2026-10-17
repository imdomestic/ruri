# 执行指令：将 ruri 中的 vex 前端做成实验性功能（R1）

- 日期：2026-10-17
- 仓库：`imdomestic/ruri-chorus`
- 上游：`https://github.com/guh0613/ruri.git` 的 `main`
- 设计依据：vex 仓库的 `docs/design/vex.md` v0.2 第 12 节
- 本指令取代 vex P0/P1 指令中的 1F

## 目标

1. 让 fork 和上游之间只差一个默认关闭、自成一体的 vex 实验性功能，可以直接作为 PR 合回上游。上游发布后，再随上游版本进入 nixpkgs。
2. 用户在 ruri 设置里打开这项功能后，GUI 和 CLI 才会出现现有的服务器页、Git 页和对应的命令。
3. 关闭这项功能时，ruri 的行为与上游完全一致。

## 规则

- **分支**：从最新的上游 `main` 新建 `feat/vex-experimental`，把现有代码移植过来，不要在旧分支上继续叠改动。提交要拆小，每个提交单独看都能被审阅，可以直接拿来组成上游 PR 系列。
- **遵守上游约定**：代码风格、本地化（xcstrings 加上游的校验脚本）和测试都按上游来。不得通过修改 `scripts/lib/localization-baseline.json` 或 `localization-exceptions.json` 来绕过校验。
- **测试不依赖真实环境**：上游 CI 必须能在无网络、无 vex 服务器的环境中通过。依赖真实环境的测试，在 `VEX_IT_URL` 未设置时一律跳过。
- **不引入新依赖**：不新增第三方 Swift 依赖。确实需要时，先在报告里说明理由，等用户决定。
- **不对外联系上游**：不要联系上游维护者，也不要向 `guh0613/ruri` 提 issue 或 PR。这些由用户决定和执行。

## 步骤

### 1. 给现有差异分类

当前 fork 相对基线 `4353f8d` 改了 58 个文件，在报告中逐个列出，归入下面三类。

**(a) 独立应用隔离，全部撤销**

包括：

- `Resources/Info.plist`、`Resources/GameHost-Info.plist` 中的标识和名称；
- `Resources/RuriSigning.cer`、`scripts/build-app.sh`、`scripts/release/signing.py`；
- `SoftwareUpdater`（Sparkle 的关闭）；
- `Authentication`、`CurseForgeKeyStore` 中的独立钥匙串；
- `LauncherPaths` 中的独立数据目录；
- `CLIInstallation`、`CommandHelp` 中的独立 CLI 名称；
- `LocalizationContext` 中的独立语言设置；
- `RuriApp` 中的独立窗口标题；
- 对本地化 baseline 和 exceptions 文件的修改。

**(b) 功能接入，保留但必须受开关控制**

包括：

- `AppModel`。这里把服务器列表设成了主页面，必须恢复上游的默认主页；
- `Page`、`RootView`、`ServersView`、`PreferencesView`；
- CLI 的注册、命令发现、schema、帮助文本和文本渲染；
- `Package.swift` 和 `Package.resolved`。先查清这两个文件为什么被改。

**(c) 通用修复，各自拉独立分支，作为单独的上游 PR**

已知的有 `Launch.swift` 中 26.3 SDL 窗口的正常退出处理。先确认上游最新 `main` 是否已经修复，如果已修复就丢弃这一项。

### 2. 重命名与去硬编码

- 代码、字符串、设置键、钥匙串条目名中的 Chorus 一律改为 Vex。CLI 子命令改为 `ruri vex …`。
- 删除所有硬编码内容，包括 encore 的地址、Team ID、`/Users/linwhite` 路径。服务器地址由用户在设置里填写。
- vex 相关代码集中放在 `Sources/Ruri/Features/Vex/`、`Sources/RuriCore/Vex/`、`Sources/RuriCommandKit/Vex*` 和对应的测试目录中。接入点用 `// MARK: Vex (experimental)` 标注。

### 3. 实验性开关

- 设置项为 `experimental.vex.enabled`，默认 `false`，存放在上游现有的设置存储里，GUI 和 CLI 读同一个值。
- 设置界面新增「实验性功能」分区，内容包括开关、一段说明，以及服务器地址和 token 的配置。地址和 token 的配置只在开关打开后显示。CLI 用上游已有的配置命令修改这个值，先查清上游有哪个命令可用。
- **开关关闭时：**
  - 不显示任何 vex 页面，服务器页也不接入 vex 内容；
  - 不发起任何网络请求，不读钥匙串，不运行后台 SSE；
  - CLI 的 `vex` 命令组不出现在帮助、命令发现和 schema 中；
  - 直接调用 `ruri vex …` 时，报错并提示如何开启。
- **运行时切换：** 关闭开关后立即断开 SSE、隐藏页面，不需要重启应用。重新打开后恢复。

### 4. 托管实例与模组同步

- 保留现有的安全行为：托管模组做 SHA 校验，非托管文件保留。
- vex 托管实例放在上游数据目录中，用实例标记来区分，不再使用独立目录。
- 不迁移旧独立应用的数据：托管实例重新 prepare，Microsoft 账号重新登录一次。
- 把模组同步逻辑抽成接口，为 R2 做准备。R2 会在 vex P2 提供 mrpack 后，改用上游 `RuriCore/Modpacks/MRPack.swift` 的导入和更新流程，并删除自定义的 manifest 同步。

### 5. 对接 vex API v2（vex P1）

- 改用 `/v2` 接口，并新增项目选择器，数据来自 `GET /v2/projects`。
- 房间、构建、提交视图都带上项目信息。
- SSE 按项目过滤。
- 房间地址直接使用 API 返回的值。
- CLI 增加 `--project` 参数。
- 已有 token 继续可用，因为 vex 只是改为存储它的哈希。

## 验收

1. **改动范围**：执行 `git diff upstream/main --stat`，vex 专属目录以外的改动只能是接入点。在报告中逐个列出这些接入点并说明理由，目标是少于 15 个文件。
2. **上游测试**：在开关默认关闭的状态下，上游测试套件和本地化校验都能原样通过。
3. **开关关闭时与上游一致**：
   - CLI 的 `help`、命令发现和 schema 输出与上游基线逐字节相同，写成 golden 测试；
   - GUI 的侧栏和主页与上游相同，附截图。
4. **开关打开后的真实联测**：连上 vex P1 服务器，服务器页和 Git 页可用；对 chorus 的 main 房间和 example 项目的分支房间，都能完成 prepare、launch 并进入游戏。
5. **构建与签名**：使用上游的构建脚本能成功构建，仓库中不包含 fork 自己的签名身份。
6. **报告内容**：报告写在 `docs/reports/<日期>-ruri-vex-r1.md`，包括差异分类表、接入点清单、开关两种状态的截图、测试结果，以及已经可以提交上游的通用修复分支列表。

## 后续阶段（本轮不做）

- **R2**：在 vex P2 之后，改为基于 mrpack 同步，并支持 PR 预览链接。
- **R3**：在 vex P4 之后，订阅 `launch_intent`，实现从游戏内触发的自动重启。
- **上游 PR**：在 vex API v2 冻结后提交。在此之前，由用户先通过 issue 或 discussion 与上游维护者确认是否愿意接受。
