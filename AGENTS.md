# 项目协作规则

本文件适用于整个仓库。修改 `proxy-installer/` 时，同时遵守该目录中的 `AGENTS.md`；子目录规则补充本文件。后续迭代开始前先阅读本文件和根目录 `README.md`，再阅读当前任务相关的代码、测试与说明。

## 项目目标与当前基线

- 仓库：`bbcat2022/surge-proxy-installer`。
- 目标：用户通过 SSH 登录 Debian 13 amd64 VPS，执行一条 GitHub 安装命令，即可安装管理器并部署 Snell v6、AnyTLS 和 Hysteria2。
- 实际项目位于 `proxy-installer/`；根目录负责项目导航、协作规则和 GitHub 自动发布配置。
- 本次维护版本为 `proxy-installer-v0.1.6`，修复证书后台续期及管理器升级时的程序保留。程序版本以 `proxy-installer/manifests/` 的清单为准，不根据协议名称推断二进制能力。
- 用户已反馈三种协议均可在 iOS Surge 中连接。该结论只覆盖已实际执行的部署和连接路径，不能扩大为全部更新、卸载、恢复、重启及长期证书续期均已验收。

## 工作方式

- 按“基础能力 → 独立模块 → 模块级验证 → 编排 → 正式入口验收”的顺序推进。
- 一个任务覆盖实现、对应测试、同范围修复和文档同步。范围和授权清楚时持续执行，只在需要产品决策、新权限或超出范围的高影响操作时中断。
- 先检查现有实现和工作区差异，保留用户已有修改，不顺手重构无关模块。
- 使用自然、易懂的中文解释结果。公开使用文档侧重安装、使用、更新和排错，内部协作和资料管理细节留在开发规则中。
- 修改脚本行为时补充对应验证；纯文档变化检查事实、链接、示例和发布范围，不为文案变化机械运行全部测试。

## 资料与公开范围

- `no-upload/` 的所有内容禁止提交到 GitHub，也禁止进入 Release、公开附件和发布包。该目录保存内部需求、技术决策、节点契约、追踪矩阵、交接资料和方法论。
- 按任务阅读相关内部文档；早期文档中的“尚未开发”等阶段描述不代表当前状态。当前实现以代码和测试核实，真实验收以明确反馈或记录为证据。
- 不公开个人信息、VPS 地址、真实测试域名、生效配置、密码、Token、证书或私钥。示例使用假值。
- 项目专属真实值如需加入排除检查，只写入被忽略的 `.private-upload-denylist`。实际凭据不得写入普通文档或测试。
- `no-upload/` 只表示禁止公开发布，不提供加密，也不阻止系统同步和备份。
- 发布前检查暂存差异和发布包内容，并运行现有检查器；不要为了通过检查删除或弱化规则。

## 工程边界

- 主配置 `/etc/proxy-installer/config.yaml` 只允许通过 `proxy-installer/tools/config_tool.py` 结构化读取和修改。
- `lib/interface/` 只负责交互，不直接写配置或调用真实系统命令。
- `lib/adapters/` 负责参数校验和配置生成，不直接写文件或调用 systemd。
- 二进制、证书、服务文件和防火墙由对应资源模块管理；高影响组合操作通过事务和编排层执行。
- 外部制品变化必须核对真实文件、SHA-256、版本、包结构和所需能力，再更新清单和测试。协议版本与程序版本分别确认。
- ACME 数据目录默认固定为 `/root/.acme.sh`，通过 `ACME_HOME` 可覆盖。签发、续期和导出必须使用相同目录，兼容已有 ECC/RSA 记录；不得依赖 SSH 会话的 HOME。导出路径必须持久存在，不使用事务临时目录。
- 管理器升级必须保留已安装的协议二进制及其 `.metadata`，同时保留失败恢复能力。
- 测试使用临时路径和假值，不写入真实 `/etc`、`/usr/local/bin`、`/etc/systemd/system`。
- 真实 VPS 操作需要明确授权范围；本地开发授权不自动包含生产环境操作。

## 相关资料入口

| 任务 | 先阅读 |
|---|---|
| 项目状态、入口与目录 | 根目录 `README.md` |
| 子项目开发 | `proxy-installer/AGENTS.md`、`proxy-installer/README.md` |
| 安装入口或管理命令 | `proxy-installer/docs/github-release-install.md` |
| 协议或版本清单 | 对应适配器、注册表、`proxy-installer/manifests/README.md` 和清单 |
| 测试与真实验收 | `proxy-installer/docs/local-preacceptance-coverage.md`、相关测试及内部验收计划 |
| 需求、职责或接口变化 | `no-upload/` 中对应的基线、节点契约和追踪矩阵 |
| 开发流程与复盘 | `no-upload/vibe-coding-methodology/` |

## 每次迭代的文档同步

文档同步是任务完成条件。每次迭代结束前检查以下映射，只更新与本次变化有关的内容：

| 变化 | 同步更新 |
|---|---|
| 项目目标、目录、入口、支持范围或真实验收结论 | 根目录 `README.md`，必要时更新子项目 `README.md` |
| 协作方式、工程边界、验证或发布流程 | 本文件及相关子目录 `AGENTS.md` |
| 菜单、参数、默认值、安装、更新或证书使用方式 | 子项目 `README.md` 和 `docs/github-release-install.md` |
| 协议实现或外部制品 | 对应清单、`manifests/README.md`、相关使用说明和测试 |
| 测试覆盖、真实验收或未验证范围 | `docs/local-preacceptance-coverage.md`；详细内部证据放入 `no-upload/` |
| 产品决策、节点职责、接口或需求状态 | `no-upload/` 中对应的基线、契约和追踪记录 |

执行要求：

1. 保留已冻结的历史结论；根据已授权的需求变化明确记录替代关系，不把旧假设默认为现状。
2. 区分“已实现”“本地测试通过”“目标环境已验证”和“已发布”。本地检查脚本输出只说明本次本地检查，不能代替历史或新增真实验收。
3. 版本状态来自本地标签、提交或明确发布记录；未核对 GitHub 时不声称它是上游最新版本。
4. 对同一事实检查相关文档是否一致，避免根目录写“已验证”、安装说明仍写“未验收”。
5. README 记录当前可用状态和入口，不堆积逐次任务日志；详细决策和过程保存到内部记录。
6. 在结尾说明同步了哪些文档、运行了哪些验证，以及仍未验证的范围。与本次改动无关的文档无需为了更新时间而修改。

## 常用验证命令

以下命令均在仓库根目录执行。

```bash
# 自动化测试；读取根目录 .python-packages/ 中的本地依赖
bash proxy-installer/bin/test.sh

# 发布前完整本地检查：测试、打包、解包运行检查
bash proxy-installer/bin/preacceptance.sh --verify --report proxy-installer/dist/preacceptance-report.txt

# 提交或发布前检查
python3 proxy-installer/tools/publication_guard.py --root . --mode staged
python3 proxy-installer/tools/publication_guard.py --root . --mode tracked
```

`staged` 仅检查已暂存文件，`tracked` 仅检查已跟踪文件；新建且未暂存的文件需要另外检查。提交、推送和创建正式版本按用户授权执行，不因补写文档而自动发布。

文档基线更新：2026-11-11。
