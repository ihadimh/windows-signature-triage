# windows-signature-triage

给 [DeepSeek Harness](https://github.com/deepseek-ai)（以及任何采用 `.agents/skills` 约定的 agent）用的**一个**技能：Windows 签名故障排查。

装上之后，当你说"这个 exe 提示签名无效"、"证书不受信任"、"无法验证此文件的签名"时，agent 会自动按这套流程走，而不是猜。

## 它解决什么

系统报"签名无效"至少有四种完全不同的原因，**处置方式相反**：

| 现象 | 常见误判 | 真实原因 | 正确处置 |
|---|---|---|---|
| `OfflineRevocation` | 证书坏了 | 网络不通 / OCSP 被墙 | 换网络，别删证书 |
| `NotSigned` | 文件被篡改 | 可能只是**目录签名** | 查 `.cat`，别重装系统 |
| 签名者证书已过期 | 签名失效 | 有时间戳则**仍然有效** | 验时间戳，别重签 |
| `NotTrusted` | 根证书有毒 | 缺中间证书 | 装中间证书 |

技能内容包含：四问决策树、命令模板、输出解读、以及一份**红线清单**（不许建议关校验、关杀软、加白名单、删根证书）。

## 安装

**方式一：脚本（推荐）**

```powershell
.\install.ps1
```

脚本会优先用同目录的 `SKILL.md`；没有就依次从 GitHub、ghproxy、gitmirror 下载。
**写出的是无 BOM 的 UTF-8**——带 BOM 会让 frontmatter 解析失败，技能被静默丢弃（这个坑已经踩过）。

**方式二：git clone**

```powershell
git clone https://github.com/ihadimh/windows-signature-triage.git "$env:USERPROFILE\.dsh\skills\windows-signature-triage"
```

目录名必须和仓库名一致——DSH 按 `<技能名>/SKILL.md` 发现技能。
国内网络访问 github.com 经常超时，连不上就用方式一或方式三。

**方式三：只复制文件**

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.dsh\skills\windows-signature-triage"
curl.exe -L -o "$env:USERPROFILE\.dsh\skills\windows-signature-triage\SKILL.md" `
  https://raw.githubusercontent.com/ihadimh/windows-signature-triage/main/SKILL.md
```

装完**重启会话**生效。验证：问一句"你有哪些 skill"。

### 装完先自检

```powershell
.\verify-install.ps1
```

它会检查三类**不会报错、只会让技能静默消失**的问题：

| 检查 | 后果 |
|---|---|
| 文件带 UTF-8 BOM | frontmatter 解析失败，技能不被加载 |
| frontmatter 的值里有 `: ` | YAML 当成嵌套映射，整段解析失败 |
| `name` 与安装目录名不一致 | 扫描不到 |

前两条都真的发生过一次。脚本还会模拟安装一遍，并在有 `install.ps1` 时跑一次端到端安装。

## 装在哪

| 位置 | 作用范围 | 优先级 |
|---|---|---|
| `<项目>\.dsh\skills` | 该项目 + 团队 | 100 |
| `<项目>\.agents\skills` | 同上（通用约定） | 200 |
| `%USERPROFILE%\.dsh\skills` | 本机所有项目 | 400 |

个人用选第三个，团队共享选第一个（跟仓库走）。

## 机器可读的归因规则

如果想让 agent 直接读结构化规则（而不是从 Markdown 里抠），用这份：

**https://raw.githubusercontent.com/ihadimh/certdiag/main/docs/rules.json**

```json
{"version": 1,
 "verdicts": ["valid", "invalid", "unknown"],
 "rules": [{"id": "valid_revocation_unchecked", "verdict": "valid",
            "title": "签名有效，但未检查吊销",
            "when": "--revoke=off（默认），或 auto 档因地址不可达而放弃",
            "action": "需要吊销结论时加 --revoke=cache 或 --revoke=auto"}],
 "red_lines": ["不建议关闭签名校验 / 关闭杀软 / 加入白名单", "..."]}
```

它由 certdiag 的覆盖率测试保证与代码同步——**代码里出现的每个分类都必须在这张表里有说明**。

## 技能里包含什么

- 四问决策树（签名在哪 / 证书还是网络 / 过期与时间戳 / 没签名还是文件坏了）
- 吊销四档的判读方式（`--revoke=off|cache|auto|online`）
- 常见 `category` 对照表与退出码语义
- 红线清单（不许建议关校验、关杀软、加白名单、删根证书）
- 一条容易被忽略的前置判断：**文件本身损坏时，签名结论没有意义**

## 配合使用

这个技能会调用 [certdiag](https://github.com/ihadimh/certdiag) 做实际诊断：

```bash
python -m certdiag "C:\path\to\app.exe"
```

没装 certdiag 也能用——技能里带了 `Get-AuthenticodeSignature`、`sigcheck` 等替代手段的判断流程。

## 格式说明

DSH 只认两种形态：`<root>/<name>/SKILL.md` 或 `<root>/<name>.md`，**嵌套的 `**/SKILL.md` 不会被发现**。

frontmatter 必填 `name` 和 `description`。几个坑：

- `name` 必须与目录名一致
- 布尔类字段写错（如 `disable-model-invocation: 是`）会导致整个技能被静默丢弃
- 改正文不用重启；改 `name` 或新增技能需要重新扫描

## 已知限制

| 项 | 说明 |
|---|---|
| `git clone` 在国内常超时 | 优先用 `install.ps1`（带 ghproxy / gitmirror 镜像回退） |
| 需要 `signtool` 的步骤 | 它属于 Windows SDK，默认没装；技能里已标注 |
| `sigcheck` | Sysinternals 单独下载；技能里已标注 |
| 正文是中文 | 触发描述里加了英文关键词，英文提问也能命中 |

## 许可

MIT
