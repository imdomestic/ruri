# 2026-10-15 推送前完整历史检查

## 仓库与范围

GitHub CLI 2.100.0 确认 github.com 当前身份为 `linwh1te`，具有目标仓库的 admin、push 权限。用户创建的 `imdomestic/ruri-chorus` 为公开 fork，所有者为 `imdomestic`，上游为 `guh0613/ruri`。本地已添加 `origin`，保留 `upstream`。检查时远端仅有 `main = 4353f8d046a11e59c64ce58e5f4f6ae6ac3e5f6c`。

| 待推送引用 | 检查时 SHA |
| --- | --- |
| `dev` | `6404d883466aa78844802a6eb81b6e5d764c5ad8` |
| `feat/p3-ruri-servers` | `d69e2793ea2d4c16fc734db07c8c24cc3bd5f767` |
| `feat/p4-ruri-git` | `6404d883466aa78844802a6eb81b6e5d764c5ad8` |

三个引用的完整可达历史共 327 个提交，包含全部上游历史；仓库没有浅克隆边界。各提交完整文件树共有 4,200 个不同的 blob，共 66,280,174 字节，最大单个文件为 1,706,882 字节。当前范围没有 merge commit。

## 方法与覆盖

- 使用 Gitleaks 8.30.1 默认规则，并增加签名下载 URL、Chorus/Microsoft 凭据赋值、用户 TOML token 规则。所有报告启用 `--redact=100`。使用空 `.gitleaksignore`，禁用行内 `gitleaks:allow`，没有为候选增加忽略规则；保留工具默认规则自带的判断条件。
- Git 扫描使用 `--root --diff-merges=separate --full-history dev feat/p3-ruri-servers feat/p4-ruri-git`，覆盖根提交和全部历史修改。另用 GitPython 3.2.1 遍历每个提交的完整文件树，按 blob SHA 去重提取所有文件对象，再独立扫描；这包括历史删除文件以及每个提交最终保存的文件内容。若以后出现 merge commit，同样会扫描其完整文件树。
- 文件对象提取直接读取 Git 对象数据库，不依赖工作目录和 `.gitignore`；当前 `.work/` 中的构建、会话、认证辅助资料未被提交，也没有被加入本次推送范围。最大文件限制设为零，不因大小省略文件。文件对象扫描启用归档深度 3、内容解码深度 5。
- Gitleaks 对部分二进制格式和默认路径有跳过规则，因此另外使用 GNU strings 2.46 提取 ASCII、8 位、UTF-16/UTF-32 大小端可读字符串，并再次扫描。`file` 5.47 对全部对象分类；四份历史 DER 证书通过 OpenSSL 4.0.3 解析后重新输出与原始字节完全相等，均为公开 X.509 证书。
- 两个 PNG 使用 Pillow 11.3.0 校验、读取，其元数据字典均为空；五个 SVG 的文本也包含在补充扫描中。唯一 JAR 由 Python 标准 `zipfile` 校验并读取全部三个成员，扫描解压后的 manifest、service 声明和 class 可读字符串。二进制扫描覆盖公开结构、元数据和可读字符串，不包含图像隐写检测。
- 327 个提交的提交消息、作者和提交者字段单独扫描。另检查全部历史路径中的 SSE、日志、`users.toml`、secret/credential 文件名，以及私钥/证书扩展名；未发现前一类文件，后一类仅为上述公开证书。
- 除通用凭据规则外，针对性规则检查资源签名 URL、Microsoft access/refresh token、client secret、固定 token 和密码赋值。候选值仅在审阅进程内比较，文档和报告不记录原值。

## 检查结果

Git 历史修改扫描报告 4 条候选；全部文件对象扫描报告 14 条候选，来自这些内容的历史版本。逐项检查确认它们为下列上游内容，未发现真实凭据。

| Git 扫描候选位置 | 引入提交 | 核验依据 |
| --- | --- | --- |
| `scripts/lib/localization-baseline.json:2028` | `de1059de5b6d551eafbf0dc4b12b7e38aac6bcff` | 本地化工具生成的 12 位十六进制摘要；生成函数取规范 JSON 的 SHA256 前 12 位。 |
| `Tests/RuriCoreTests/Accounts/AccountAppearanceTests.swift:35` | `96be5f4ecc12bcdb31a6197411a7c04430ee5a22` | 上游账号外观测试中的固定字面量，传入该测试的 session，并用于日志脱敏断言。 |
| 同文件 `:85` | 同上 | 上游测试固定字面量，具有对应脱敏断言。 |
| 同文件 `:112` | 同上 | 与上一项相同的测试字面量，在另一个脱敏断言中使用。 |

文件对象扫描的 14 条候选包括五个本地化文件版本中的同一摘要，以及三个测试文件版本中的九处字面量；进程内比较确认仅涉及一个摘要值和两个测试值。二进制补充扫描、提交消息扫描均为零候选。补充路径与签名 URL 检查没有发现凭据。扫描过程中没有运行这些上游测试。

新增本报告和验收记录修改后，另外扫描当前文档文件；结果为零候选。应用源码与三个待推送引用未改变。任何新增提交均需要核对新增内容后再推送。

## 本地证据

全部中间资料位于被 Git 忽略的 `.work/`。原始扫描报告仅保留完全脱敏版本：

- `.work/round2-h-gitleaks-redacted.json`、`.work/round2-h-gitleaks.log`：327 个提交的历史修改检查。
- `.work/round2-h-blob-manifest.json`、`.work/round2-h-blobs-redacted.json`、`.work/round2-h-blobs-scan.log`：完整文件对象清单和检查。
- `.work/round2-h-review.json`、`.work/round2-h-binary-review.json`：候选分类、历史路径、MIME 分类及重复内容核验。
- `.work/round2-h-binary-extraction.json`、`.work/round2-h-binary-redacted.json`、`.work/round2-h-messages-redacted.json`：证书、图像元数据、JAR、可读字符串及提交消息检查。
- `.work/round2-h-docs-redacted.json`、`.work/round2-h-docs-scan.log`：新增报告及当前文档检查。
- `.work/round2-h.log`：身份、远端、引用与检查结果。
