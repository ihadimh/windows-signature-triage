---
name: windows-signature-triage
description: 诊断 Windows 代码签名失败（签名无效、证书不受信任、证书过期、"无法验证此文件的签名"、哈希不匹配），区分"证书真的坏了"与"只是查不到吊销状态"。当用户报告签名错误、要求验证下载/分发的 exe/dll、或问"为什么 Windows 说这个程序签名无效"时使用。
whenToUse: 用户提到签名无效、无法验证签名、证书过期/不受信任/被吊销、哈希不匹配，或需要批量校验一堆可执行文件的签名时。
---

# Windows 签名故障排查

## 核心原则

系统报"签名无效"至少有四种完全不同的原因，**处置方式相反**。不先分类就动手，通常会把好文件删掉、把正常证书换掉。

| 现象 | 常见误判 | 真实原因 | 正确处置 |
|---|---|---|---|
| `OfflineRevocation` / 提示"吊销状态未知" | 证书坏了 | 网络不通、代理拦截、OCSP 端点被墙 | 换网络或配代理，**不要删证书** |
| `NotSigned` / "无法验证" | 文件被篡改 | 可能只是**目录签名**（签名不在文件里） | 查 `.cat`，**不要重装系统** |
| 签名者证书已过期 | 签名失效 | 有时间戳则签名**仍然有效** | 验时间戳，**不要重签** |
| `NotTrusted` | 根证书有毒 | 缺中间证书，或根未部署 | 装中间证书 |

**红线**（任何情况下都不要建议）：
- 关闭系统签名校验、关闭杀软、把文件加白名单
- 删除或替换系统根证书
- 用"破解/去校验"类工具
- 把"查不到吊销状态"说成"证书无效"

## 四问决策树

按顺序问，每一步都能砍掉一半可能性。

### 一问：签名在文件里，还是在目录里？

```
文件属性 → 数字签名 标签页 为空，但系统仍判有效？
  → 目录签名（catalog）：签名在 C:\Windows\System32\CatRoot\{GUID}\*.cat
  → 用 certdiag 看 catalog 字段，或 sigcheck -a 看 Catalog 列
```

系统文件（`cmd.exe`、`notepad.exe`、多数驱动）通常是目录签名：**PE 安全目录为空**，但 PowerShell 判有效、`WinVerifyTrust` 返回 `TRUST_E_NOSIGNATURE`。这不是矛盾，是两个 API 视野不同。

### 二问：是证书问题，还是网络问题？

```
结论里出现"吊销""revocation""CRL""OCSP"字眼
  → 先测网络：curl -I <CRL 地址> 或 certdiag 的 probe 结果
  → CRL 可达 + OCSP 不确定  = 大概率网络问题，不是证书问题
  → CRL 不可达 + 报 OfflineRevocation = 确定是网络问题
```

**判据**：`unknown ≠ invalid`。查不到吊销状态只说明"没查到"，不说明"证书有问题"。

### 三问：过期了吗？有没有时间戳？

```
签名者证书已过期 + 有时间戳 → 按签名时刻评估，通常仍然有效
签名者证书已过期 + 无时间戳 → 确实失效
```

时间戳的意义：证明"签名发生在这个时间点"，让过期证书的历史签名继续有效。

### 四问：是"没签名"还是"签名对不上"？

| 状态 | 含义 | 是否可疑 |
|---|---|---|
| `NotSigned` + 无目录签名 | 从未签名 | 视来源而定，**不等于被篡改** |
| `HashMismatch` | 内容与签名不符 | **高度可疑**，文件被改过 |
| `TRUST_E_BAD_DIGEST` | 同上，更精确的错误码 | **高度可疑** |

## 命令模板

```bash
# 1) 单文件，看结论与依据
python -m certdiag "C:\path\to\app.exe"

# 2) 机器可读，便于后续判断
python -m certdiag app.exe --json report.json

# 3) 不联网（只看链与有效期，排除网络干扰）
python -m certdiag app.exe --offline

# 4) 批量（目录），看有没有未签名/无效的
python -m certdiag "C:\Program Files\XX" -q --no-probe

# 5) 图形界面
python -m certdiag --ui
```

没有 certdiag 时的等价手段：

```powershell
Get-AuthenticodeSignature <文件> | Format-List Status, StatusMessage, SignerCertificate
# 看目录签名
sigcheck -a <文件>     # Sysinternals，需要额外下载
certutil -verify -urlfetch <文件>
```

## 输出解读

certdiag 的 `diagnosis` 字段是判据：

| `verdict` | 含义 | 后续动作 |
|---|---|---|
| `valid` | 通过 | 无需处理 |
| `invalid` | 确定有问题 | 按 `category` 定位：`hash_mismatch` 说明被改过；`untrusted_root` 说明缺根/中间证书 |
| `unknown` | **无法判定** | 通常是网络/离线导致，换环境重试，**不要说成"无效"** |

关键 `category`：
- `catalog_only_trust` — 无嵌入签名，信任来自 `.cat`，**正常**
- `revocation_unreachable` — 吊销地址不可达，**网络问题**
- `expired_with_timestamp` — 证书过期但有时间戳，**通常仍有效**
- `hresult:TRUST_E_BAD_DIGEST` — 内容被改过，**可疑**

## 回复用户时的结构

1. **结论**：有效 / 无效 / 无法判定（三选一，不要含糊）
2. **依据**：状态 + 错误码 + 目录签名情况（一两行）
3. **下一步**：具体动作，且必须是只读或可逆的
4. **不要做**：明确列出不该做的事（关校验、删证书、加白名单）

如果结论是 `unknown`，必须说明"这不能证明文件有问题，只说明本次没查到"，并给出重试方式（换网络/加代理/离线复核）。
