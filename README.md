# dsh-skills

给 [DeepSeek Harness](https://github.com/deepseek-ai) 用的技能集合。每个技能是一份写给人看、也写给 agent 看**操作手册**，装上之后 agent 遇到对应场景会自动套用这套流程。

## 有哪些技能

| 技能 | 什么时候用 | 说明 |
|---|---|---|
| [`windows-signature-triage`](windows-signature-triage/SKILL.md) | Windows 报"签名无效/无法验证/证书过期/不受信任" | 区分"证书真的坏了"与"只是查不到吊销状态"。附带"四问决策树"和一份红线清单 |

## 安装

### 方式一：一键脚本

```powershell
irm https://raw.githubusercontent.com/ihadimh/dsh-skills/main/install.ps1 | iex
```

### 方式二：git clone

```powershell
git clone https://github.com/ihadimh/dsh-skills.git "$env:TEMP\dsh-skills"
Copy-Item "$env:TEMP\dsh-skills\*\SKILL.md" -Destination "$env:USERPROFILE\.dsh\skills" -Force -Recurse
```

> 注意：上面这条要求 `.dsh\skills` 下已有同名目录；不确定就先手动建目录再复制。

### 方式三：手动

把 `windows-signature-triage/SKILL.md` 复制到：

```
C:\Users\<你>\.dsh\skills\windows-signature-triage\SKILL.md
```

**目录名必须和 frontmatter 里的 `name` 一致**，否则会被静默忽略。

## 安装到哪里

DSH 按下面的顺序扫描技能根目录（rank 小的优先）：

| Rank | 路径 | 适用 |
|---|---|---|
| 100 | `<项目根>\.dsh\skills` | 团队共享，跟仓库走 |
| 200 | `<项目根>\.agents\skills` | 同上（通用约定） |
| 300 | 配置项 `customSkillDirs` | 自定义 |
| 400 | `C:\Users\<你>\.dsh\skills` | **个人全局（推荐）** |
| 500 | `<agentsHome>\skills` | 其他 agent 工具共用 |

## 格式要求

```markdown
---
name: windows-signature-triage        # 必填，需与目录名一致
description: 一句话说明何时该用我       # 必填，模型靠它决定是否选中
whenToUse: 更细的触发条件              # 可选
metadata:                             # 可选
  author: you
disable-model-invocation: false       # 可选，true = 模型看不到
user-invocable: true                  # 可选，false = 不出现在人工命令里
---

# 正文（操作手册）
```

几个坑：

- 只认 `<root>/<name>/SKILL.md` 或 `<root>/<name>.md`，**嵌套的 `**/SKILL.md` 不会被发现**
- 布尔字段写错（比如 `disable-model-invocation: 是`）会导致**整个技能被丢弃**，且没有明显报错
- 改正文不用重启；改 `name` 或新增技能需要重新扫描

## 校验

仓库里的技能可以用 certdiag 自带的校验脚本检查：

```powershell
python tools/check_skill.py
```

## 许可

MIT
