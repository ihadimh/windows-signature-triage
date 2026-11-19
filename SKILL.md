---
name: windows-signature-triage
description: 诊断 Windows 代码签名失败（签名无效、证书不受信任、证书过期、"无法验证此文件的签名"、哈希不匹配、文件疑似损坏），区分"证书真的坏了""只是查不到吊销状态""文件本身不完整"三种情况。当用户报告签名错误、要求验证下载/分发的 exe/dll、或问"为什么 Windows 说这个程序签名无效"时使用。
whenToUse: 用户提到签名无效、无法验证签名、证书过期/不受信任/被吊销、哈希不匹配，或需要批量校验一堆可执行文件的签名时。Also use for: "signature invalid", "untrusted certificate", "this app can't run", "verify Authenticode signature of a downloaded exe/dll".
---

# Windows 签名故障排查

## 先取证，再下结论

系统报"签名无效"至少有四类原因，**处置方式相反**。不先分类就动手，通常会把好文件删掉、把正常证书换掉。

三条工作原则：

1. **别信任何错误码表，包括这份技能里的。** 用系统自己的工具核对：
   ```powershell
   certutil -error 0x800B010D     # → CERT_E_UNTRUSTEDTESTROOT（不是吊销离线！）
   certutil -error 0x80092013     # → CRYPT_E_REVOCATION_OFFLINE（这才是吊销离线）
   ```
   这两条是真实踩过的坑：把 0x800B010D 当成吊销离线，会把"测试根不受信"误诊成网络问题。

2. **"没查到"和"有问题"是两件事。** 结论只有三档：`valid` / `invalid` / `unknown`。
   默认只有 `invalid` 会让退出码变 1，`unknown` 不算失败。

3. **结论要能追溯。** 说"有效"必须能说清是签名通过、链通过，还是吊销也查了。

## 四问决策树

按顺序问，每一步都能砍掉一半可能性。

### 一问：签名在文件里，还是在目录里？

```
文件属性 → 数字签名 标签页 为空，但系统仍判有效？
  → 目录签名（catalog）：签名在 C:\Windows\System32\CatRoot\{GUID}\*.cat
  → certdiag 看 catalog 字段；或 sigcheck -a 看 Catalog 列
```

系统文件（`cmd.exe`、`notepad.exe`、多数驱动）通常是目录签名：**PE 安全目录为空**，
但 PowerShell 判有效、`WinVerifyTrust` 返回 `TRUST_E_NOSIGNATURE`。这不是矛盾，是视野不同：

| API | 能看到 | 看不到 |
|---|---|---|
| `Get-AuthenticodeSignature` | 嵌入签名 + 目录签名回退 | 不给精确 HRESULT |
| `WinVerifyTrust` | 精确 HRESULT | 不查目录签名 |

**注意**："找到了 .cat"不等于"这个 .cat 可信"，还要看 `.cat` 自身的签名状态。

### 二问：是证书问题，还是网络问题？

```
出现吊销/CRL/OCSP 字样
  → 先确认吊销到底查没查：certdiag 报告里的「吊销：」一行
  → 没查（--revoke=off）就不能下"证书坏了"的结论
  → 查了但失败 → 网络问题
```

**判据**：`unknown ≠ invalid`。查不到吊销状态只说明"没查到"。

### 三问：过期了吗？有没有时间戳？

```
签名者证书已过期 + 时间戳令牌签名有效 → 按签名时刻评估，通常仍然有效（置信度 medium）
签名者证书已过期 + 无时间戳           → 确实失效
```

时间戳的边界：只验"令牌本身没被篡改"不等于"可信时间戳"。
完整校验还需要 messageImprint 绑定、TSA 用途（EKU）、TSA 链时效——certdiag 不做这三项，
需要完整结论时用 `signtool verify /pa /t`（需装 Windows SDK）。

### 四问：是"没签名"、"签名对不上"，还是"文件坏了"？

| 情况 | 分类 | 是否可疑 |
|---|---|---|
| 从未签名，也无目录签名 | `no_signature` | 视来源而定，**不等于被篡改** |
| 内容与签名不符 | `hresult:TRUST_E_BAD_DIGEST` / `hash_mismatch` | **高度可疑** |
| 扩展名是 exe 但内容不是 PE | `not_pe_file` | 多半是改了扩展名或下载坏了 |
| PE 头在、证书表越界 | `corrupt_pe` | **文件被截断**，先重新下载 |

最后两类：**别去查签名策略**。文件本身不完整时，任何签名结论都没有意义。

## 吊销：先问"查了没"，再问"查到了什么"

certdiag 的 `--revoke` 有四档，结论措辞跟着档位走：

| 档位 | 行为 | 结论 |
|---|---|---|
| `off`（默认） | 不查，报告写「吊销：未检查（--revoke=off）」 | `valid_revocation_unchecked`（medium） |
| `cache` | 只读本地 CRL 缓存，毫秒级 | 命中 → `checked_ok`；未命中 → 未检查 |
| `auto` | 先探地址，可达才联网查 | 查到 → `checked_ok`；不可达 → 未检查 + 原因 |
| `online` | 强制联网（慢，2~30 秒） | 同上 |

只有真的拿到结果才会出现 `valid_revocation_checked_ok`；被吊销则直接 `invalid`。

## 先确认工具在哪

| 情况 | 怎么做 |
|---|---|
| 有便携版 | 解压 `certdiag-portable-*.zip`，用 `runtime\python.exe -m certdiag` |
| 有源码 | 在仓库目录用 `python -m certdiag`（纯标准库，无需 pip） |
| 都没有 | 用下面的 PowerShell 替代流程，不要硬编一个"结论" |

便携版在 Release 里：`https://github.com/ihadimh/certdiag/releases`（约 11 MB，自带运行时，免装 Python）。

## 命令模板

```bash
# 1) 单文件，看结论与依据
python -m certdiag "C:\path\to\app.exe"

# 2) 想知道吊销状态（推荐 auto：先探路再决定要不要查）
python -m certdiag app.exe --revoke=auto

# 3) 完全离线（不探测、不联网查吊销、不下载中间证书）
python -m certdiag app.exe --offline

# 4) 批量巡检，只要汇总
python -m certdiag "C:\Program Files\XX" -q --no-probe

# 5) 当签名门禁用：无签名也算失败（退出码 1）
python -m certdiag "D:\release" --require-signature

# 6) 机器可读
python -m certdiag app.exe --json report.json
```

没有 certdiag 时的等价手段：

```powershell
# 1) 粗状态（会回退查目录签名）
Get-AuthenticodeSignature .\app.exe | Format-List Status, StatusMessage, SignerCertificate

# 2) 想看链和吊销抓取日志：certutil 只接受证书文件，先导出签名者证书
$c = (Get-AuthenticodeSignature .\app.exe).SignerCertificate
[IO.File]::WriteAllBytes("$env:TEMP\signer.cer", $c.Export('Cert'))
certutil -verify -urlfetch "$env:TEMP\signer.cer"

# 3) 看目录签名（需 Sysinternals）
sigcheck -a .\app.exe

# 4) 核对错误码含义
certutil -error 0x800B010D
```

> 踩过的坑：`certutil -verify` 直接喂 exe 会报 `CRYPT_E_ASN1_BADTAG`——它只解析证书容器。

## 输出解读

`diagnosis.verdict` 是判据：

| verdict | 含义 | 后续动作 |
|---|---|---|
| `valid` | 通过 | 无需处理 |
| `invalid` | 确定有问题 | 按 `category` 定位 |
| `unknown` | **无法判定** | 通常网络/离线/文件损坏，换条件重试，**别说成"无效"** |

常见 `category`：

| 分类 | 含义 |
|---|---|
| `catalog_only_trust` | 无嵌入签名，由有效的 `.cat` 覆盖，**正常** |
| `valid_revocation_checked_ok` | 签名、链、吊销都已检查通过 |
| `valid_revocation_unchecked` | 签名有效，但**吊销没查** |
| `revoked` | 证书已被吊销 → invalid |
| `expired_with_timestamp_signature_ok` | 过期但令牌签名有效（medium，不等于可信时间戳） |
| `catalog_unverified` / `catalog_hash_mismatch` | `.cat` 状态不明 / `.cat` 自身校验失败 |
| `corrupt_pe` / `not_pe_file` | 文件不完整 / 内容不是 PE |
| `hresult:TRUST_E_BAD_DIGEST` | 内容被改过，**可疑** |

## 退出码

| 码 | 含义 |
|---|---|
| 0 | 全部有效（`unknown` 不算失败） |
| 1 | 存在确定无效；或 `--require-signature` 命中无签名 |
| 2 | 存在无法判定，且用了 `--fail-on unknown` |
| 3 | 运行错误（参数冲突、文件不存在、采集失败） |

## JSON 结构（v1.6.0 起固定）

```json
{"schema_version": 1, "tool": "certdiag", "tool_version": "1.6.0",
 "generated_at": "...", "count": 2, "reports": [ ... ]}
```

单条和多条都是同一层结构——不要按"是不是数组"来分支。

## 回复用户时的结构

1. **结论**：有效 / 无效 / 无法判定（三选一，不含糊）
2. **依据**：状态 + 错误码 + 目录签名情况（一两行）
3. **下一步**：具体动作，且必须只读或可逆
4. **不要做**：明确列出不该做的事

结论是 `unknown` 时，必须说明"这不能证明文件有问题，只说明本次没查到"，并给出重试方式。

## 红线（任何情况下都不要建议）

- 关闭系统签名校验、关闭杀软、把文件加白名单
- 删除或替换系统根证书
- 用"破解/去校验"类工具
- 把"查不到吊销状态"说成"证书无效"
- 在文件本身损坏（`corrupt_pe`）的情况下讨论签名结论
