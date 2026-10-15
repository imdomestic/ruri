# Ruri Chorus

独立应用标识为 `dev.ruri.launcher.chorus`，数据目录为 `~/Library/Application Support/Ruri Chorus`。Microsoft 凭据、Chorus token、CLI 安装记录使用独立标识。Sparkle 更新关闭。

接口依据为 chorus-testbed 的 `docs/api.md`。上游为 `https://github.com/guh0613/ruri.git` 的 `main` 分支，本地 `dev` 主线以提交 `4353f8d046a11e59c64ce58e5f4f6ae6ac3e5f6c` 为基线；本地修改集中在 `Chorus/` 目录，现有应用的接入位置带有 `CHORUS` 注释。

构建与打包：

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
export TMPDIR="$PWD/.work/tmp"
export RURI_BUILD_DIR="$PWD/.work/build"
mkdir -p "$TMPDIR"
scripts/swift-build.sh -c debug --build-system swiftbuild
scripts/build-app.sh debug --build-system swiftbuild
```

产物为 `build/Ruri Chorus.app`，其中 CLI 位于 `Contents/Helpers/ruri-cli`。安装 CLI 后使用 `ruri-chorus`。

本地打包固定使用 `Resources/RuriSigning.cer` 对应的 Apple Development 身份，当前证书指纹为 `0B74E9A9640121629B281DAABCA88E6D4D46487E`，Team ID 为 `59ZC6MZ73T`。GUI 与 CLI 共用 `dev.ruri.launcher.chorus` 签名标识，打包时验证二者的 designated requirement 完全一致；身份不可用时立即终止打包。ruri-monitor 与 RuriGame 不读取钥匙串凭据。

首次签名时为 codesign 选择“始终允许”；首次打开新签名版本时，为已有 Chorus 钥匙串条目完成授权。以后仅使用 `/Users/linwhite/ruri-chorus/build/Ruri Chorus.app`。更换证书时，通过 Xcode 安装包含私钥的 Apple Development 身份，将对应公钥证书导出为 DER 并更新 `Resources/RuriSigning.cer`，重新打包后核对 Team ID 和 GUI/CLI 的 designated requirement。旧条目再次请求授权时选择“始终允许”，随后重新构建并验证授权保持；只有授权仍不能生效时，才删除独立应用的 `dev.ruri.launcher.chorus.*` 条目并重新登录、配置 token。

`chorus configure --url http://encore.inner.imdomestic.com:8790 --token-stdin` 从标准输入接收 token 并存入钥匙串。不要把 token 写进命令参数。`chorus rooms`、`chorus builds` 查询真实后端；`chorus start main-fabric` 请求启动；`chorus prepare main-fabric` 准备真实游戏、Java 和模组并等待房间就绪；`chorus launch main-fabric --dry-run` 检查已安装文件并生成启动计划。`--launch` 和实际 `launch` 需要在独立应用中登录账号。

Chorus token 按规范化后端 URL 保存在进程内缓存；首次访问读取钥匙串，后续 API 调用和 SSE 重连直接复用。成功保存 token 时同步更新缓存，用户保存连接设置后会重新读取所选地址的条目。

启动操作固定目标房间的 generation 和 buildId，服务端 ready 与本地文件准备全部满足后只启动一次。托管模组通过 SHA256 校验并原子交换目录；非托管模组保留并提示。取消加入操作会撤销该操作取得的租约。

Chorus 托管实例使用 Java 游戏进程，设置 `macOS.enabled=false`。首次创建游戏设置文件时关闭 VSync、辅助功能引导和失去焦点暂停；已有游戏设置文件保持原样，其他实例设置继续保留。

通用服务器列表过滤当前 `/v1/meta` zone、曾用 zone（包含 `100-64-0-43.sslip.io`）下的地址，以及仅关联 Chorus 托管实例的条目。地址比较规范化大小写、端口和结尾点，并按 DNS 标签边界判断。游玩历史继续保存。

每次启动托管实例前，以及游戏正常退出后，程序在持有实例运行租约时清理 `servers.dat` 中属于这些 zone 的隐藏条目。清理使用现有 NBT 组件，保留其他条目和未知字段，先原子保存 `servers.dat.ruri-backup`，检查文件未被并发修改后原子替换。启动时固定目录的 canonical path、device 和 inode，退出时核对，目录被替换或重定向时停止清理。与非托管实例共享游戏目录时停止启动并显示原因；清理发生错误时记录在会话中。monitor 使用启动时核对并传入的目录和 zone，无需读取钥匙串。

服务器页的 Chorus 分区提供最近 7 天关闭的临时房间，按关闭时间显示最多 10 个，可重新开启并加入。明确重新开启已关闭且标记完成的房间时，先把标签恢复为 testing，再启动新的 generation；普通启动保持完成标签限制。Git 页与 Chorus 分区的刷新按钮等待服务端 Git 更新完成后重新加载；实时 Git 事件也会重新加载提交历史。encore 根分区可用空间低于 20 GiB 时，Chorus 分区显示剩余空间提示。

离线测试覆盖状态机、manifest 校验、地址限制、数据隔离；真实联测读取 `CHORUS_IT_URL`，从该 URL 对应的独立钥匙串条目读取 token。`CHORUS_SSE_RECORDING` 指向真实 chorusd 录制数据，用于离线事件解码测试。既有上游中使用替代依赖的测试不纳入本项目的无 mock 验收。

Git 页面从后端读取分支与拓扑排序的提交历史，分页保留父节点连接，展示各 loader 的构建状态并提供日志、构建和临时房间操作。CLI 对应 `chorus branches`、`chorus commits --branch main`、`chorus build <完整 SHA>`、`chorus create <完整 SHA> --branch main`。`chorus build-log <buildId> --token-stdin --json` 查询完整构建状态与原始日志；界面日志窗口同时显示服务端错误。

无人值守联测可以设置 `CHORUS_IT_SSH_HOST=encore`，测试进程通过 BatchMode SSH 从指定 secret 文件读取 linwhite token，在内存中解析并用于真实 API。CLI 的 `chorus prepare` 与 `chorus launch` 支持 `--token-stdin`，凭据通过管道传入。应用凭据保存在钥匙串中。
