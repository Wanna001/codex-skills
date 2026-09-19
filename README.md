# Codex Skills

自用的 [Codex](https://openai.com/codex/) skill 集合。每个 `skills/<skill-name>/` 目录都是一个可独立安装的
skill：复制到 `%USERPROFILE%\.codex\skills\`（或 `$env:CODEX_HOME\skills\`）下，Codex 就会自动发现并在
合适的时候启用它。

当前收录 **1** 个 skill：

| Skill | 一句话说明 |
| --- | --- |
| [windows-cjk-script-encoding](skills/windows-cjk-script-encoding/SKILL.md) | 让 Windows 脚本（`.ps1` / `.psm1` / `.bat` / `.cmd` / `.py`）里的中文不再乱码：硬性编码规则 + 双宿主实测矩阵 + 可挂 CI 的 `-Check` / `-Fix` 门禁脚本 |

目录：[它解决什么问题](#它解决什么问题) · [快速开始](#快速开始) · [编码规则速查](#编码规则速查) ·
[检查/修复工具](#检查--修复工具) · [接入 CI / pre-commit](#接入-ci--pre-commit) · [实测矩阵](#实测矩阵) ·
[常见症状对照](#常见症状对照) · [目录结构](#目录结构) · [新增 skill 的约定](#新增-skill-的约定) ·
[许可证](#许可证)

## English

A small personal collection of Codex skills. Each folder under `skills/` can be copied into
`%USERPROFILE%\.codex\skills\` and Codex will pick it up automatically.

Current skill: **windows-cjk-script-encoding** — keeps Chinese/CJK text working in Windows scripts
(`.ps1` / `.psm1` / `.bat` / `.cmd` / `.py`). It ships the hard encoding rules (UTF-8 **with** BOM for
PowerShell, UTF-8 + `chcp 65001` + CRLF for batch, explicit `encoding="utf-8"` for Python), a
compatibility matrix measured on real hosts, and a `-Check` / `-Fix` CLI that can be wired into CI
or a pre-commit hook.

## 它解决什么问题

写 `.ps1` / `.bat` 时，只要文件里出现中文就可能翻车，而且往往**不是"显示不好看"，是脚本直接跑不动**：

| 现象 | 真实原因 |
| --- | --- |
| `powershell.exe` 输出 `涓枃杈撳嚭`，同一个文件用 `pwsh` 却正常 | 文件是 UTF-8 **无 BOM**，Windows PowerShell 5.1 按系统 ANSI(936) 解析它 |
| `if ($msg -eq "中文")` 永远不成立、`Substring()`/正则莫名其妙不匹配 | 乱码后字符串**长度都变了**（`中文输出` 从 7 个字符变 9 个），逻辑前提已经错掉 |
| 批处理报 `'xxx' 不是内部或外部命令`，`goto`/标签失效 | 批处理被存成 LF 行尾（必须是 CRLF），或存成了 UTF-16 |
| 批处理里中文输出成 `涓枃娴嬭瘯` | 文件是 UTF-8 却没有 `chcp 65001`，或 `chcp` 写在中文行**之后** |
| Python 写出的配置/日志别的程序读不了 | `open()` 默认用系统 locale（中文 Windows = cp936），不是 UTF-8 |
| 同一个会话里"前一条命令正常、后一条全乱" | `chcp` 改的是整个控制台的代码页，会被子进程带跑 |

根因通常只有一句话：**生成文件的工具（apply_patch、编辑器、CI 产物）默认写 UTF-8 无 BOM，
而 Windows PowerShell 5.1 会把无 BOM 的文件按 ANSI 解析。**
所以"能在 `pwsh` 里跑通"并不代表"能在用户机器上跑通"。

## 快速开始

### 1. 安装 skill

```powershell
# 克隆仓库
git clone https://github.com/Wanna001/codex-skills.git
cd codex-skills

# 安装全部 skill（复制到 Codex 的 skills 目录）
Copy-Item .\skills\* "$env:USERPROFILE\.codex\skills\" -Recurse -Force

# 只安装其中一个
Copy-Item .\skills\windows-cjk-script-encoding "$env:USERPROFILE\.codex\skills\" -Recurse -Force
```

安装后在 Codex 里直接说"写一个带中文输出的 ps1，别乱码"即可命中；也可以显式调用
`$windows-cjk-script-encoding`。

### 2. 用它检查 / 修复脚本

```powershell
$gate = ".\skills\windows-cjk-script-encoding\scripts\normalize-script-encoding.ps1"

# 体检（只读，有违规时退出码 1）
pwsh -NoProfile -File $gate -Path . -Recurse -Check

# 修复（就地改写编码 / 行尾 / 补 chcp）
pwsh -NoProfile -File $gate -Path .\scripts -Recurse -Fix

# 看每个文件的判定结果
pwsh -NoProfile -File $gate -Path .\tools -Recurse -Check -Verbose
```

### 3. 用目标宿主实跑（关键一步）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\foo.ps1   # 5.1，必测
pwsh.exe       -NoProfile -ExecutionPolicy Bypass -File .\tools\foo.ps1   # 7.x
```

只测 `pwsh` 会漏掉最常见的 5.1 乱码；反过来，用户机器只有 5.1 时也别只测 7.x。
如果脚本是被 `cmd`、定时任务、GUI 或 Python 调起的，就在那个真实入口里跑一遍。

## 编码规则速查

| 文件类型 | 存储编码 | 附加要求 |
| --- | --- | --- |
| `.ps1` `.psm1` `.psd1` | 含中文时 **UTF-8 with BOM** | 唯一被 `powershell.exe`(5.1) 与 `pwsh`(7.x) 同时正确解析的编码；纯 ASCII 文件无 BOM 也无害 |
| `.bat` `.cmd` | 优先纯 ASCII；必须含中文时 UTF-8 **无** BOM | 必须 CRLF；`chcp 65001>nul` 必须出现在任何含中文的行之前 |
| `.py` `.md` `.json` `.txt` `.csv` `.yaml` `.xml` `.html` | UTF-8 无 BOM | Python 源码默认 UTF-8，但 `open()` 默认 cp936，写文件要显式 `encoding="utf-8"` |
| `.reg` | UTF-16LE | 首行保持 `Windows Registry Editor Version 5.00` |

运行期（输出侧）另需一行：

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)   # 本进程输出
$OutputEncoding           = [Console]::OutputEncoding          # 管道交给原生命令（PS 5.1 默认 us-ascii）
chcp 65001                                                     # 批处理 / 子进程
```

> 命令行**参数**以 UTF-16 传递，不会因为代码页乱码。乱码只发生在"文件字节"和"控制台显示"两处，
> 排查时先分清是哪一处，能省很多时间。

## 检查 / 修复工具

`skills/windows-cjk-script-encoding/scripts/normalize-script-encoding.ps1`

读取文件时自动判定编码：`EF BB BF` → UTF-8 with BOM；`FF FE` → UTF-16LE；`FE FF` → UTF-16BE；
无 BOM 时做**严格 UTF-8** 解码，通过即视为 UTF-8；失败则按系统 ACP（中文 Windows = 936）解码。

| 参数 | 说明 |
| --- | --- |
| `-Path <string[]>` | 必填，文件 / 目录 / 通配符，可多个 |
| `-Recurse` | 目录递归 |
| `-Check` | 只读检查（不写 `-Fix` 时的默认行为） |
| `-Fix` | 就地改写，把文件规整到策略要求的编码 |
| `-BatchMode Utf8Chcp` / `Ansi` | 批处理策略：默认 `Utf8Chcp`（UTF-8 + 自动补 `chcp 65001`）；`Ansi` 则改存 ANSI(936) 并补 `chcp 936`，适合只在中文 Windows 跑的旧脚本 |
| `-SourceEncoding Auto` / `Utf8` / `Ansi` | 源编码判定；个别 GBK 文件恰好也能通过 UTF-8 校验时，用 `Ansi` 强制指定 |
| `-StrictBom` | 连纯 ASCII 的 `.ps1` 也要求带 BOM（团队想统一风格时用） |
| `-Verbose` | 打印每个文件的判定结果（`[OK] ...`） |

退出码：`0` 无违规 / `1` 存在（未修复的）违规 / `2` 路径无效。

`-Fix` 做什么：`.ps1` 补 UTF-8 BOM；`.bat`/`.cmd` 统一 CRLF、去掉 BOM、把 `chcp` 挪到任何中文行之前；
`.py`/`.md`/`.json` 等统一成 UTF-8 无 BOM。纯 ASCII 的文件不会被刷出无意义 diff。

不依赖脚本的手工兜底（仅用于已确认是 UTF-8 的 `.ps1`，补 BOM）：

```powershell
$p = '.\tools\foo.ps1'
[IO.File]::WriteAllText($p, [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), [Text.UTF8Encoding]::new($true))
```

反过来，**不要**用 `Get-Content` / `ReadAllText` 的默认编码读一个 GBK 文件再写回 UTF-8：
解码阶段插入的替换字符会永久损坏内容。先确定源编码（`-SourceEncoding Ansi`）再改写。

## 接入 CI / pre-commit

GitHub Actions（纯文本门禁，不需要第三方依赖）：

```yaml
name: encoding-gate
on: [push, pull_request]
jobs:
  scripts-encoding:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check script encodings
        shell: pwsh
        run: |
          ./skills/windows-cjk-script-encoding/scripts/normalize-script-encoding.ps1 -Path . -Recurse -Check
```

本机 pre-commit 钩子（`.git/hooks/pre-commit`，Git for Windows 下可直接用）：

```sh
#!/bin/sh
pwsh -NoProfile -File ./skills/windows-cjk-script-encoding/scripts/normalize-script-encoding.ps1 -Path . -Recurse -Check || {
  echo "编码门禁未通过：请运行 -Fix 后再提交" >&2
  exit 1
}
```

## 实测矩阵

实测环境：Windows 11 build 26200，系统 ACP/OEMCP = 936（简体中文），Windows PowerShell 5.1.26100，
PowerShell 7.6.5。完整数据、复现方法与 Git 侧注意事项见 references/encoding-matrix.md（位于 skill 目录内）。

`.ps1`（执行结果）：

| `.ps1` 存储编码 | `powershell.exe`（5.1） | `pwsh.exe`（7.x） |
| --- | --- | --- |
| UTF-8 无 BOM（多数工具默认） | **乱码** `涓枃杈撳嚭 ok`，长度 9 | 正常 |
| UTF-8 with BOM | 正常 | 正常 |
| UTF-16LE（BOM） | 正常 | 正常 |
| GBK / ANSI(936) | 正常 | **乱码** `������� ok`，长度 10 |

`.bat` / `.cmd`（cmd.exe，受控制台代码页影响）：

| 文件编码 | 行尾 | chcp | 结果 |
| --- | --- | --- | --- |
| UTF-8 无 BOM | CRLF | 无 | 控制台(936) 显示 `涓枃娴嬭瘯` |
| UTF-8 无 BOM | CRLF | 首部 `chcp 65001>nul` | 正常 |
| GBK / ANSI(936) | CRLF | 控制台 936 | 正常 |
| GBK / ANSI(936) | CRLF | 控制台 65001 | 乱码 `锟斤拷...` |
| UTF-8 无 BOM | **LF only** | 任意 | `'xxx' 不是内部或外部命令`，标签失效 |
| UTF-16LE | CRLF | 任意 | 无法解析 |

## 常见症状对照

| 你看到的 | 处置 |
| --- | --- |
| `涓枃杈撳嚭`、`涓枃娴嬭瘯` | 典型 UTF-8 被当 GBK 读：`.ps1` 补 BOM，或给批处理补 `chcp 65001` |
| `锟斤拷` | 编码转换中产生了替换字符，通常已经损坏；用 `-SourceEncoding` 指定源编码重试 |
| `'xxx' 不是内部或外部命令` | 批处理行尾不是 CRLF，或文件是 UTF-16 → `-Path x.bat -Fix` |
| 只在 PowerShell 5.1 出错 | 文件缺 BOM → `-Path . -Recurse -Fix` |
| 只在 PowerShell 7 出错 | 文件是 GBK/ANSI → 同上；7.x 默认按 UTF-8 读源码 |
| 输出到文件就乱、屏幕上正常 | 输出侧编码问题：用 `[Console]::OutputEncoding` / `PYTHONIOENCODING=utf-8` |
| 前一条命令正常、后一条乱 | 批处理里的 `chcp` 改了共享控制台代码页，需在每个入口显式声明编码 |

## 目录结构

```text
codex-skills/
├── README.md
├── .gitattributes                                    # *.ps1/*.bat/*.cmd 固定 CRLF
└── skills/
    └── windows-cjk-script-encoding/
        ├── SKILL.md                                  # Codex 载入的指令：硬性规则 + 工作流
        ├── agents/
        │   └── openai.yaml                           # UI 元数据（显示名、默认提示词）
        ├── references/
        │   └── encoding-matrix.md                    # 实测矩阵、复现方法、Git 侧注意事项
        └── scripts/
            └── normalize-script-encoding.ps1         # 检查 / 修复工具
```

## 新增 skill 的约定

1. 用 `skills/<skill-name>/` 存放，名字用小写字母、数字和连字符。
2. 必须有 `SKILL.md`，YAML frontmatter 至少包含 `name` 与 `description`；`description` 要写清
   "做什么 + 什么时候用"，它决定 Codex 何时自动启用这个 skill。
3. 需要脚本 / 参考资料时放 `scripts/`、`references/`，并在 `SKILL.md` 里指路。
4. 只写"能改变决策"的内容：已知结论、非显然的坑、可复用的脚本；不要复制通用教程。
5. 新增或改动后跑一次结构校验（skill-creator 自带的校验器，需要 PyYAML）：

   ```powershell
   python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\quick_validate.py" .\skills\<skill-name>
   ```

## 环境要求

- Windows 10 / 11（实测 Windows 11 build 26200，中文区域 ACP=936）
- Windows PowerShell 5.1 与 / 或 PowerShell 7.x：仓库内脚本在两者下均可运行
- 无第三方依赖，纯 PowerShell + .NET BCL

## 许可证

本项目采用 **MIT License**，完整条款见仓库根目录的 `LICENSE`。

这意味着任何人都可以自由地使用、复制、修改、合并、发布、分发、再许可甚至出售本项目的副本，
唯一要求是保留版权声明与许可声明；软件按"原样"提供，不附带任何形式的担保。

如果你只是想把这里的编码规则或检查脚本用到自己的项目里，直接用即可，不必事先询问。
