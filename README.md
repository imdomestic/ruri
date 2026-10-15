# Ruri Chorus

适用于 macOS 的 Minecraft Java 启动器，提供 Chorus 服务器列表、Git 提交浏览和临时测试房间。

## 下载与安装

[下载 Ruri Chorus 0.10.6（Universal DMG）](https://github.com/imdomestic/ruri-chorus/releases/download/chorus-v0.10.6/Ruri-Chorus-0.10.6-macOS-universal.dmg) · [发布记录](https://github.com/imdomestic/ruri-chorus/releases)

支持 macOS 14 或更新版本，安装包同时包含 Apple Silicon 和 Intel 两种架构。

1. 下载并打开 DMG，将 **Ruri Chorus.app** 拖入 **Applications**。
2. 从“应用程序”打开 Ruri Chorus。如果 macOS 提示开发者无法验证，请打开“系统设置 → 隐私与安全性 → 仍要打开”，再确认打开。当前安装包使用 Apple Development 签名，尚未经过 Apple 公证；操作步骤见 [Apple 官方说明](https://support.apple.com/en-ie/102445)。
3. 登录自己的 Microsoft 账号。使用 Chorus 房间时，在设置中填写管理员提供的服务器地址和个人 token，并连接服务器所在的网络。

Ruri Chorus 与原版 Ruri 可以同时安装，账号、实例和设置分别保存。

## 功能

- 在服务器页启动并进入 Chorus 房间，自动下载与构建匹配的模组。
- 浏览 Git 分支与提交，为指定提交创建临时房间。
- 查看构建状态和失败日志，通过内置 CLI 查询服务器、构建与房间。

## 构建与发布

开发、签名和接口说明见 [CHORUS.md](CHORUS.md)，发布步骤见 [发布文档](docs/releasing.md)，已有验证记录见 [CHORUS-VALIDATION.md](CHORUS-VALIDATION.md)。

本项目基于 [guh0613/ruri](https://github.com/guh0613/ruri)，使用 [GPL-3.0 许可证](LICENSE)。每个 Release 对应的源码可从该版本标签下载。
