# Ruri Chorus 验证记录

2026-10-15，Xcode 26.6、Swift 6.3.3、macOS SDK 26.5。构建使用 `--build-system swiftbuild`，临时目录为仓库中的 `.work/tmp`。

## 应用与数据

- 应用：`build/Ruri Chorus.app`；标识：`dev.ruri.launcher.chorus`；CLI：`Contents/Helpers/ruri-cli`。
- 支持目录：`~/Library/Application Support/Ruri Chorus`。Microsoft 凭据、Chorus token、偏好设置、CLI 安装记录均使用独立标识。
- Sparkle 已禁用。应用采用 ad hoc 签名，`codesign --verify --deep --strict` 通过。首次使用钥匙串时可能需要授权当前构建。
- 此分支开发和测试没有读取或写入已安装 Ruri 的数据目录。

## 已运行的检查

- Debug 构建、应用打包、签名检查、CLI 命令发现、JSON/NDJSON 输出、辅助进程、应用移动后的 CLI 链接检查通过。
- 回归检查共 142 个测试通过：monitor/runtime 10 个、本地化 6 个、Core/Chorus 110 个、CLI 16 个。日志：`.work/test-runtime.log`。SDL 正常退出能力检查使用独立应用实际安装的 Minecraft 26.3 manifest，并验证托管运行设置保留其他配置、已有游戏设置文件保持原样。
- 检查采用纯函数、实际文件、SQLite、进程和真实 chorusd；上游使用替代依赖的测试不属于本次执行范围。
- 真实 API 验证了 meta、房间、构建、分支、提交分页和初次 SSE sync。真实 SSE 录制验证事件解码。模组检查下载真实构建产物，验证 SHA256、增删托管文件、保留非托管文件及拒绝已损坏的托管文件。
- Git 图检查覆盖合并提交、多个父节点、独立根提交、分页边界及无效拓扑输入；构建状态和日志入口通过编译及真实模型读取验证。
- 真实 `prepare` 与 `launch --dry-run` 完成：`cfc16eaac-fabric`，generation 3，build `fabric-fc16eaac252b`。独立实例使用 Java 25、Fabric KnotClient、76 个 classpath 文件，QuickPlay 指向服务端返回的房间主机，结果明确包含 `authenticationRequired=true`。
- 应用打包日志：`.work/build-runtime-app.log`。实际启动计划记录位于 chorus-testbed 的 `.work/logs/ruri-dry-run.json`，不含凭据。

## 验收待办

- 用户在 Ruri Chorus 登录 Microsoft 账号后，验证服务器页面自动进入和 Git 页面旧提交临时房间进入。阶段分支保持独立，尚未合入 `dev`。
- 旧提交的构建与 `prepare`/`dry-run` 验证等待服务端资源验收安排；真实进入仍需要上述登录。
- Minecraft 26.3 的 SDL 已纳入正常退出能力判定。实际 Java 游戏进程接受 `NSRunningApplication.terminate()` 后记录 `Stopping!`，会话结果为 `succeeded`、退出代码 0；该系统请求与 `NativeGameQuit.request` 相同。Chorus 托管实例使用已验证的 `macOS.enabled=false` 设置，首次创建游戏设置时关闭 VSync、辅助功能引导和失去焦点暂停。

## 联测设置

临时联测地址为 `http://127.0.0.1:18790`，经 SSH 转发到 encore。生产地址为 `http://encore.inner.imdomestic.com:8790`。Chorus token 保存在独立钥匙串；无人值守 CLI 可以通过 `--token-stdin` 接收，测试可以通过显式配置的 BatchMode SSH 在内存中读取。凭据不进入参数、日志或文档。
