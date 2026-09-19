---
name: windows-cjk-script-encoding
description: Keep Chinese/CJK (中文) text working in Windows scripts and consoles — .ps1/.psm1/.psd1, .bat/.cmd, .py, and data files. Use when writing, generating, or editing scripts that contain 中文, when output shows 涓枃/锟斤拷/乱码, when a script only misbehaves on Windows PowerShell 5.1, or when a repo needs an encoding gate in CI or a pre-commit hook.
metadata:
  short-description: Windows 中文脚本编码防乱码
---

# Windows 中文脚本编码

## 硬性规则

| 文件类型 | 存储编码 | 附加要求 |
| --- | --- | --- |
| `.ps1` `.psm1` `.psd1` | 含中文时必须 **UTF-8 with BOM** | 唯一被 `powershell.exe`（5.1）和 `pwsh`（7.x）同时正确解析的编码；纯 ASCII 文件无 BOM 也无害（`-StrictBom` 可强制统一） |
| `.bat` `.cmd` | 优先纯 ASCII；必须含中文时 UTF-8 **无** BOM | 必须 CRLF；`chcp 65001>nul` 必须出现在任何含中文的行之前 |
| `.py` `.md` `.json` `.txt` `.csv` `.yaml` `.xml` `.html` | UTF-8 无 BOM | Python 读源码默认 UTF-8，但 `open()` 默认用系统 locale（中文 Windows = cp936） |
| `.reg` | UTF-16LE | 首行保持 `Windows Registry Editor Version 5.00` |

三个真实坑（均为本机实测，数据见 `references/encoding-matrix.md`）：

- **主因**：`apply_patch`、多数编辑器、CI 产物写出的 `.ps1` 是 UTF-8 **无 BOM**；PS 5.1 按系统 ANSI(936) 解析它，`中文输出` 变成 `涓枃杈撳嚭`。字符串长度随之变化（7 → 9），还会连带破坏比较、路径拼接和正则匹配，所以经常表现为"命令直接跑不了"而不是"只是显示难看"。
- `.bat`/`.cmd` 存成 LF 行尾或 UTF-16 → cmd 报 `'xxx' 不是内部或外部命令`，`goto`/标签失效。
- `.bat`/`.cmd` 是 UTF-8 但 `chcp 65001` 写在中文行之后 → 已解析过的行仍按旧代码页解码，输出照旧是 `涓枃娴嬭瘯`。`chcp` 必须在最前面。

## 工作流：写含中文的脚本

1. 正常生成/编辑文件。
2. 落盘后立即规整编码（相对本 SKILL.md 所在目录）：

   ```powershell
   pwsh -NoProfile -File scripts/normalize-script-encoding.ps1 -Path .\tools\foo.ps1 -Fix
   ```

3. 用**目标宿主**实跑，看输出而不是看文件：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\foo.ps1   # 5.1（必测）
   pwsh.exe       -NoProfile -ExecutionPolicy Bypass -File .\tools\foo.ps1   # 7.x
   ```

   只测 `pwsh` 会漏掉最常见的 5.1 乱码；反过来，用户机器只有 5.1 时也别只测 7.x。若脚本是被 `cmd`、GUI、定时任务或 Python 调起的，就在那个真实入口里跑一遍。

4. 交付前做一次批量体检，避免只修了新增文件：

   ```powershell
   pwsh -NoProfile -File scripts/normalize-script-encoding.ps1 -Path . -Recurse -Check
   ```

## 检查 / 修复工具

`scripts/normalize-script-encoding.ps1` 按上表套策略，自动识别 BOM / UTF-8 / ANSI(ACP)，PS 5.1 与 7.x 都能跑：

```powershell
# 只检查（只读，有违规时退出码 1，可直接挂 CI / pre-commit）
pwsh -NoProfile -File scripts/normalize-script-encoding.ps1 -Path . -Recurse -Check

# 就地修复
pwsh -NoProfile -File scripts/normalize-script-encoding.ps1 -Path .\scripts -Recurse -Fix

# 面向只在中文 Windows 运行的旧环境：批处理改存 ANSI(936)
pwsh -NoProfile -File scripts/normalize-script-encoding.ps1 -Path .\setup.bat -Fix -BatchMode Ansi

# 个别 GBK 文件被误判为 UTF-8 时，强制指定源编码
pwsh -NoProfile -File scripts/normalize-script-encoding.ps1 -Path .\legacy.ps1 -Fix -SourceEncoding Ansi

# 团队要求所有 .ps1 一律带 BOM（含纯 ASCII 文件）
pwsh -NoProfile -File scripts/normalize-script-encoding.ps1 -Path . -Recurse -Fix -StrictBom
```

不依赖脚本的兜底写法（仅用于已确认是 UTF-8 的 `.ps1`，补 BOM）：

```powershell
$p = '.\tools\foo.ps1'
[IO.File]::WriteAllText($p, [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), [Text.UTF8Encoding]::new($true))
```

反过来，**不要**用 `Get-Content` / `ReadAllText` 的默认编码去读一个 GBK 文件再写回 UTF-8：解码阶段插入的替换字符会永久损坏内容。先确认源编码（`-SourceEncoding`）再改写。

## 运行期：控制台与子进程

文件编码只保证"脚本能被正确解析"，显示与管道还要单独管：

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)   # 本进程输出
$OutputEncoding           = [Console]::OutputEncoding           # 管道给原生命令（PS 5.1 默认 us-ascii）
chcp 65001                                                      # 批处理 / 子进程的控制台代码页
```

- Python：`PYTHONUTF8=1`（或 `-X utf8`）让 `open()`、stdout/stderr 走 UTF-8；写文件一律显式 `encoding="utf-8"`；从 PowerShell/cmd 调 Python 时同时给子进程 `PYTHONIOENCODING=utf-8`。
- 命令行**参数**以 UTF-16 传递，不会因代码页乱码；乱码只发生在"文件字节"和"控制台显示"两处，排查时先分清是哪一处。
- PS 5.1 写文件：`Set-Content` 默认 ANSI 无 BOM，`-Encoding UTF8` 才是 UTF-8 **带** BOM；PS 7 默认 UTF-8 无 BOM，需要 BOM 时用 `-Encoding utf8BOM`。两者语义相反，跨版本共用脚本时改用 `[IO.File]::WriteAllText($p, $text, [Text.UTF8Encoding]::new($true))`。

## 参考资料

- `references/encoding-matrix.md`：实测矩阵（PS 5.1 / PS 7 / cmd × 各编码与行尾）、症状对照、复现与验证命令、Git 侧注意事项。
