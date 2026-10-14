# Ruri Chorus

独立应用标识为 `dev.ruri.launcher.chorus`，数据目录为 `~/Library/Application Support/Ruri Chorus`。Microsoft 凭据、Chorus token、CLI 安装记录使用独立标识。Sparkle 更新关闭。

接口依据为 chorus-testbed 的 `docs/api.md`。上游为 `https://github.com/guh0613/ruri.git` 的 `dev` 分支；本地修改集中在 `Chorus/` 目录，现有应用的接入位置带有 `CHORUS` 注释。

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

`chorus configure --url http://encore.inner.imdomestic.com:8790 --token-stdin` 从标准输入接收 token 并存入钥匙串。不要把 token 写进命令参数。`chorus rooms`、`chorus builds` 查询真实后端；`chorus start main-fabric` 请求启动；`chorus prepare main-fabric` 准备真实游戏、Java 和模组并等待房间就绪；`chorus launch main-fabric --dry-run` 检查已安装文件并生成启动计划。`--launch` 和实际 `launch` 需要在独立应用中登录账号。

启动操作固定目标房间的 generation 和 buildId，服务端 ready 与本地文件准备全部满足后只启动一次。托管模组通过 SHA256 校验并原子交换目录；非托管模组保留并提示。取消加入操作会撤销该操作取得的租约。

Chorus 托管实例使用 Java 游戏进程，设置 `macOS.enabled=false`。首次创建游戏设置文件时关闭 VSync、辅助功能引导和失去焦点暂停；已有游戏设置文件保持原样，其他实例设置继续保留。

离线测试覆盖状态机、manifest 校验、地址限制、数据隔离；真实联测读取 `CHORUS_IT_URL`，从该 URL 对应的独立钥匙串条目读取 token。`CHORUS_SSE_RECORDING` 指向真实 chorusd 录制数据，用于离线事件解码测试。既有上游中使用替代依赖的测试不纳入本项目的无 mock 验收。

Git 页面从后端读取分支与拓扑排序的提交历史，分页保留父节点连接，展示各 loader 的构建状态并提供日志、构建和临时房间操作。CLI 对应 `chorus branches`、`chorus commits --branch main`、`chorus build <完整 SHA>`、`chorus create <完整 SHA> --branch main`。

无人值守联测可以设置 `CHORUS_IT_SSH_HOST=encore`，测试进程通过 BatchMode SSH 从指定 secret 文件读取 linwhite token，在内存中解析并用于真实 API。CLI 的 `chorus prepare` 与 `chorus launch` 支持 `--token-stdin`，凭据通过管道传入。应用凭据保存在钥匙串中。
