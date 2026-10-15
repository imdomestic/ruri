# Ruri Chorus 发布

正式源码位于 `dev`，版本标签使用 `chorus-v<版本号>`，例如 `chorus-v0.10.6`。发布包为经过优化的 Universal 应用，包含 arm64 和 x86_64，最低系统版本为 macOS 14。

## 本地构建

使用包含私钥的既定 Apple Development 身份，证书与 GUI/CLI 的要求见 `CHORUS.md`。发布不导出私钥。

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
export TMPDIR="$PWD/.work/tmp"
export RURI_BUILD_DIR="$PWD/.work/build"
export RURI_VERSION=0.10.6
export RURI_BUILD_NUMBER=22
export RURI_CURSEFORGE_API_KEY=
mkdir -p "$TMPDIR"
scripts/package-dmg.sh
```

打包使用 `--build-system swiftbuild`。应用保留在 `build/Ruri Chorus.app`；DMG 和 SHA256 文件位于 `build/dmg/`。DMG 包含应用、Applications 快捷入口与 GPL 许可证。

## 发布检查

- 核对 GUI、CLI、monitor、RuriGame 和支持库的两个架构、签名与最低系统版本。
- 使用实际打包的 CLI 分别以 arm64 和 Rosetta x86_64 执行版本、帮助和命令检查，完成实际函数、文件与录制数据测试。
- 挂载 DMG，验证应用签名和 SHA256，再验证 GUI 启动。
- 使用 Gitleaks 检查新提交及安装包，凭据、个人账号数据和日志不进入 Release。
- 构建与检查通过后提交，创建版本标签；从该标签发布 DMG、校验文件及安装说明。
- 从 GitHub 下载发布附件，重新核对大小、SHA256 与 DMG 完整性。

当前证书为 Apple Development，安装包尚未经过 Apple 公证。发布说明应包含首次打开步骤；[Apple 公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)要求 Developer ID 签名和相应运行时配置。

GitHub 默认分支使用 `dev`。本仓库的发布由上述本地签名流程完成；继承的 GitHub Actions 工作流限定在上游仓库执行。
