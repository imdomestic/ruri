# 上游 CLI golden

这四份文件由未修改的 `guh0613/ruri` 上游 `ebcf5ab663b46e85efbfe12a50a33bbdeb426bec` 的 `ruri-cli` 真实输出生成。构建使用原有 `scripts/swift-build.sh --build-system swiftbuild -c debug --product ruri-cli`。

语言为 `zh-Hans`，数据目录为不存在的专用验收目录。命令依次为 `help`、`help --all`、`schema --json`、`schema --full --json`。文件没有 token、账号或机器路径。`VexCommandTests.disabledCommandsMatchUpstreamGoldenBytes` 逐字节核对默认关闭时的输出。
