# Ruri Chorus 验证记录

2026-10-15，Xcode 26.6、Swift 6.3.3、macOS SDK 26.5。构建使用 `--build-system swiftbuild`，临时目录为仓库中的 `.work/tmp`。

## 应用与数据

- 应用：`build/Ruri Chorus.app`；标识：`dev.ruri.launcher.chorus`；CLI：`Contents/Helpers/ruri-cli`。
- 支持目录：`~/Library/Application Support/Ruri Chorus`。Microsoft 凭据、Chorus token、偏好设置、CLI 安装记录均使用独立标识。
- Sparkle 已禁用。应用使用 Apple Development 证书 `0B74E9A9640121629B281DAABCA88E6D4D46487E`、Team ID `59ZC6MZ73T`；`codesign --verify --deep --strict` 与全部辅助程序的证书检查通过。GUI/CLI 的 designated requirement 完全一致，签名标识为 `dev.ruri.launcher.chorus`。
- 此分支开发和测试没有读取或写入已安装 Ruri 的数据目录。

## 已运行的检查

- 第二轮缓存检查 8 项通过，覆盖首次读取、重复读取、并发访问、失败保留、保存更新和设置失效；使用纯缓存状态与真实文件，测试未访问钥匙串。日志：`.work/test-token-cache-round2.log`。首次 Apple Development 签名打包及随包 CLI 验证通过，日志：`.work/round2-a-build-first.log`。
- 第二轮完整回归 184 项通过，包括主回归 144 项与附加检查 40 项；联网测试只通过 SSH 在内存中取得凭据，日志：`.work/round2-a-regression.log`。生产 Chorus token 由签名 CLI 配置；再次签名打包后，真实 `chorus rooms` 在 0.134 秒内返回成功，日志：`.work/round2-a-build-final.log`、`.work/round2-a-rooms-final.json`。
- 源码调用链与二进制符号核验确认：只有 GUI 与 CLI 使用 SecItem 读取、保存凭据，全部 service 名均带 `dev.ruri.launcher.chorus` 前缀。monitor 的 RSA 密钥仅用于内存签名，RuriGame 不访问钥匙串。
- 用户确认最终签名版本的 GUI 正常运行，刷新与点击 main-fabric 没有钥匙串授权弹窗。
- Debug 构建、应用打包、签名检查、CLI 命令发现、JSON/NDJSON 输出、辅助进程、应用移动后的 CLI 链接检查通过。
- 回归检查共 144 个测试通过：monitor/runtime 10 个、本地化 6 个、Core/Chorus 112 个、CLI 16 个。本轮真实 API、录制数据与实际游戏 manifest 检查全部执行，日志：`.work/test-final-regression.log`。SDL 正常退出能力检查使用独立应用实际安装的 Minecraft 26.3 manifest，并验证托管运行设置保留其他配置、已有游戏设置文件保持原样。
- 检查采用纯函数、实际文件、SQLite、进程和真实 chorusd；上游使用替代依赖的测试不属于本次执行范围。
- 真实 API 验证了 meta、房间、构建、分支、提交分页和初次 SSE sync。真实 SSE 录制验证事件解码。模组检查下载真实构建产物，验证 SHA256、增删托管文件、保留非托管文件及拒绝已损坏的托管文件。
- 构建 `fabric-cb7f59da8fe5` attempt 5 的真实 jar 同步测试通过，服务端专用 `chorus-hop` 未进入客户端 mods，托管客户端文件校验与非托管文件保留通过。日志：`.work/test-server-hop.log`；本次检查没有启动房间或游戏客户端。
- 生产地址 `http://encore.inner.imdomestic.com:8790` 的两个真实联网测试通过，日志：`.work/test-production.log`。额外 41 个检查通过，涵盖 manifest、内存设置、JVM 参数、会话兼容、CLI schema/输出/配置和真实失败构建录制，日志：`.work/test-additional.log`。
- 额外的真实服务切换测试通过：同一 `ChorusEventStream` 在前台 chorusd 切换到 NixOS 服务时依次收到两次 `sync`，自动重新连接完成。日志：`.work/test-reconnect.log`。
- 不可达后端检查使用系统保留且未监听的真实 TCP 端口，实际请求返回连接超时并保留可显示的错误消息；界面接入通过编译，错误消息不含凭据。
- Git 图检查覆盖合并提交、多个父节点、独立根提交、分页边界及无效拓扑输入；构建状态和日志入口通过编译及真实模型读取验证。
- 真实 `prepare` 与 `launch --dry-run` 完成：`cfc16eaac-fabric`，generation 3，build `fabric-fc16eaac252b`。独立实例使用 Java 25、Fabric KnotClient、76 个 classpath 文件，QuickPlay 指向服务端返回的房间主机，结果明确包含 `authenticationRequired=true`。
- 旧提交 `cb7f59da8fe55f6862265586db2817be66a63b8e` 的构建、房间 ready、实际模组替换、`prepare` 和 `launch --dry-run` 均完成。房间 `ccb7f59da-fabric` generation 1 使用 build `fabric-cb7f59da8fe5`，启动计划包含对应 QuickPlay 地址。记录：`.work/ruri-old-prepare.json`、`.work/ruri-old-dry-run.json`。
- 实际生产构建 `fabric-cb7f59da8fe5` attempt 2 的失败状态通过独立应用 CLI 读取；返回 `failed`、完整 `build_failed` 错误及原始日志，记录：`.work/ruri-failed-build-log.json`。真实录制模型测试验证错误字段保持完整，界面在日志窗口显示该字段。
- 实际启动计划记录位于 chorus-testbed 的 `.work/logs/ruri-dry-run.json`，不含凭据。

## 真实进入验收

- 用户确认最终签名版本的 GUI 使用过程中没有重复钥匙串授权；指定进入 main-fabric 和旧提交 cb7f59da 的目的地验收待核验。
- Minecraft 26.3 的 SDL 已纳入正常退出能力判定。实际 Java 游戏进程接受 `NSRunningApplication.terminate()` 后记录 `Stopping!`，会话结果为 `succeeded`、退出代码 0；该系统请求与 `NativeGameQuit.request` 相同。Chorus 托管实例使用已验证的 `macOS.enabled=false` 设置，首次创建游戏设置时关闭 VSync、辅助功能引导和失去焦点暂停。

## 联测设置

应用当前配置为 `http://encore.inner.imdomestic.com:8790`。服务化之前的联测通过 `http://127.0.0.1:18790` 的 SSH 转发访问 encore。Chorus token 保存在独立钥匙串；无人值守 CLI 可以通过 `--token-stdin` 接收，测试可以通过显式配置的 BatchMode SSH 在内存中读取。凭据不进入参数、日志或文档。
