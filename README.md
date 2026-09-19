# Codex Skills

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6.svg)](#环境要求)
[![Encoding gate](https://github.com/Wanna001/codex-skills/actions/workflows/encoding-gate.yml/badge.svg)](https://github.com/Wanna001/codex-skills/actions/workflows/encoding-gate.yml)

一组自用的 [Codex](https://openai.com/codex/) skill 集合。

Skill 是"指令 + 脚本 + 资源"组成的文件夹：Agent 遇到对应任务时按需加载，不必每次重复交代背景。
本仓库的每个 skill 都自包含在 `skills/<skill-name>/` 下，核心是一个带 YAML frontmatter 的 `SKILL.md`，
按 Agent Skills 约定组织，可直接被 Codex 识别，同类工具（例如 Claude Code）也能识别。

当前收录：见 [收录清单](#收录清单)；中文使用说明见下方
[Skill 详解](#skill-详解windows-cjk-script-encoding)。

> A small, self-contained collection of Codex skills. Each skill lives in `skills/<name>/` and is
> described by a `SKILL.md` with YAML frontmatter — copy it into `%USERPROFILE%\.codex\skills\` and
> Codex picks it up automatically. Current skill: **windows-cjk-script-encoding**, which keeps
> Chinese/CJK text in Windows scripts (`.ps1` / `.bat` / `.py`) from turning into mojibake.

## 关于本仓库

- **自包含**：每个 skill 一个目录，含 `SKILL.md`（指令）、`scripts/`（可执行助手）、`references/`（按需查阅的资料）。
- **零依赖**：目前收录的 skill 只用 PowerShell 与 .NET BCL，不需要 `pip` / `npm` 安装任何东西。
- **可移植**：`.ps1` 统一 UTF-8 with BOM、`.bat`/`.cmd` 统一 CRLF，跨 Windows PowerShell 5.1 与 PowerShell 7.x 验证。
- **可验证**：仓库自带编码门禁（GitHub Actions + 可复用的检查脚本），规则不只写在文档里。
- **只写"能改变决策"的内容**：已知结论、非显然的坑、可复用脚本；不复制通用教程。

## 收录清单

| Skill | 一句话说明 | 适用场景 |
| --- | --- | --- |
| [windows-cjk-script-encoding](skills/windows-cjk-script-encoding/SKILL.md) | 让 Windows 脚本里的中文不再乱码：编码硬性规则 + 双宿主实测矩阵 + `-Check` / `-Fix` 门禁脚本 | 写/改 `.ps1`、`.bat`、`.cmd`、`.py` 时出现中文；脚本只在 5.1 或只在 7.x 上出错；想给仓库加编码门禁 |

## 安装

### Codex

```powershell
git clone https://github.com/Wanna001/codex-skills.git
cd codex-skills

# 安装全部 skill
Copy-Item .\skills\* "$env:USERPROFILE\.codex\skills\" -Recurse -Force

# 只安装其中一个
Copy-Item .\skills\windows-cjk-script-encoding "$env:USERPROFILE\.codex\skills\" -Recurse -Force
```

若设置了 `CODEX_HOME`，把目标换成 `$env:CODEX_HOME\skills\`。
装好后在 Codex 里直接描述任务即可（例如"写个带中文输出的 ps1，别乱码"），也可以显式调用
`$windows-cjk-script-encoding`。

### 其他 Agent 工具

Skill 目录格式（`SKILL.md` + YAML frontmatter + 可选 `scripts/`、`references/`）是通用约定。
除 Codex 外，同样遵循该约定的工具可以直接使用这些目录，例如 Claude Code 的个人 skill 目录是
`~/.claude/skills/`。

## 仓库结构

```text
codex-skills/
├── README.md
├── LICENSE
├── .gitattributes                                  # *.ps1 / *.bat / *.cmd 固定 CRLF
├── .github/workflows/encoding-gate.yml             # 仓库自身的编码门禁
└── skills/
    └── windows-cjk-script-encoding/
        ├── SKILL.md                                # Codex 加载的指令
        ├── agents/openai.yaml                      # UI 元数据（显示名、默认提示词）
        ├── references/encoding-matrix.md           # 实测矩阵与排查手册
        └── scripts/normalize-script-encoding.ps1   # 检查 / 修复工具
```

## 创建一个新 skill

1. 新建 `skills/<skill-name>/`，名字用小写字母、数字和连字符。
2. 写 `SKILL.md`，frontmatter 至少包含 `name` 与 `description`——`description` 决定 Agent 什么时候
   自动启用这个 skill，要写成"做什么 + 什么时候用"。
3. 需要重复执行的确定性逻辑放 `scripts/`，按需查阅的长资料放 `references/`，并在 `SKILL.md` 里指路。
4. 校验结构（skill-creator 自带的校验器，需要 PyYAML）：

   ```powershell
   python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\quick_validate.py" .\skills\<skill-name>
   ```

最小 `SKILL.md` 模板：

```markdown
---
name: my-skill-name
description: 做什么，以及什么时候用它（这句决定自动启用时机）
---

# My Skill Name

## 核心规则

- 能改变决策的约束、非显然的坑、必须遵守的边界。

## 工作流

1. 先做什么，再做什么。
2. 需要时读取 `references/xxx.md` 或运行 `scripts/xxx.ps1`。
```

## Skill 详解：windows-cjk-script-encoding

### 它解决什么问题

写 `.ps1` / `.bat` 时只要文件里出现中文就可能翻车，而且往往**不是"显示不好看"，是脚本直接跑不动**：

| 现象 | 真实原因 |
| --- | --- |
| `powershell.exe` 输出 `涓枃杈撳嚭`，同一文件 `pwsh` 却正常 | 文件是 UTF-8 **无 BOM**，Windows PowerShell 5.1 按系统 ANSI(936) 解析它 |
| `if ($msg -eq "中文")` 永不成立、`Substring()` 莫名越界 | 乱码后字符串**长度都变了**（`中文输出` 从 7 个字符变 9 个），逻辑前提已错 |
| 批处理报 `'xxx' 不是内部或外部命令`，`goto`/标签失效 | 批处理被存成 LF 行尾（必须 CRLF），或存成了 UTF-16 |
| 批处理里中文输出成 `涓枃娴嬭瘯` | 文件是 UTF-8 却没有 `chcp 65001`，或 `chcp` 写在中文行**之后** |
| Python 写出的配置/日志别的程序读不了 | `open()` 默认用系统 locale（中文 Windows = cp936），不是 UTF-8 |
| 同一会话里"前一条命令正常、后一条全乱" | `chcp` 改的是整个控制台的代码页，会被子进程带跑 |

根因通常只有一句话：**生成文件的工具（apply_patch、编辑器、CI 产物）默认写 UTF-8 无 BOM，
而 Windows PowerShell 5.1 会把无 BOM 的文件按 ANSI 解析。** 所以"能在 `pwsh` 里跑通"并不代表
"能在用户机器上跑通"。

### 编码规则速查

| 文件类型 | 存储编码 | 附加要求 |
| --- | --- | --- |
| `.ps1` `.psm1` `.psd1` | 含中文时 **UTF-8 with BOM** | 唯一被 `powershell.exe`(5.1) 与 `pwsh`(7.x) 同时正确解析的编码；纯 ASCII 文件无 BOM 也无害 |
| `.bat` `.cmd` | 优先纯 ASCII；必须含中文时 UTF-8 **无** BOM | 必须 CRLF；`chcp 65001>nul` 必须在任何含中文的行之前 |
| `.py` `.md` `.json` `.txt` `.csv` `.yaml` `.xml` `.html` | UTF-8 无 BOM | Python 源码默认 UTF-8，但 `open()` 默认 cp936，写文件要显式 `encoding="utf-8"` |
| `.reg` | UTF-16LE | 首行保持 `Windows Registry Editor Version 5.00` |

输出的显示侧另需一行：

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)   # 本进程输出
$OutputEncoding           = [Console]::OutputEncoding          # 管道交给原生命令（PS 5.1 默认 us-ascii）
chcp 65001                                                     # 批处理 / 子进程
```

> 命令行**参数**以 UTF-16 传递，不会因为代码页乱码。乱码只发生在"文件字节"和"控制台显示"两处，
> 排查时先分清是哪一处。

### 检查 / 修复工具

```powershell
$gate = ".\skills\windows-cjk-script-encoding\scripts\normalize-script-encoding.ps1"

pwsh -NoProfile -File $gate -Path . -Recurse -Check          # 只读体检，有违规退出码 1
pwsh -NoProfile -File $gate -Path .\scripts -Recurse -Fix    # 就地修复
pwsh -NoProfile -File $gate -Path .\tools -Check -Verbose    # 打印每个文件的判定结果
```

判定顺序：`EF BB BF` → UTF-8 with BOM；`FF FE` → UTF-16LE；`FE FF` → UTF-16BE；无 BOM 时做
**严格 UTF-8** 解码，通过即视为 UTF-8；失败则按系统 ACP（中文 Windows = 936）解码。

| 参数 | 说明 |
| --- | --- |
| `-Path <string[]>` | 必填，文件 / 目录 / 通配符，可多个 |
| `-Recurse` | 目录递归 |
| `-Check` | 只读检查（不写 `-Fix` 时的默认行为） |
| `-Fix` | 就地改写，把文件规整到策略要求的编码 |
| `-BatchMode Utf8Chcp` / `Ansi` | 批处理策略：默认 `Utf8Chcp`（UTF-8 + 自动补 `chcp 65001`）；`Ansi` 则改存 ANSI(936) 并补 `chcp 936` |
| `-SourceEncoding Auto` / `Utf8` / `Ansi` | 源编码判定；个别 GBK 文件恰好也能通过 UTF-8 校验时用 `Ansi` 强制指定 |
| `-StrictBom` | 连纯 ASCII 的 `.ps1` 也要求带 BOM（团队想统一风格时用） |
| `-Verbose` | 打印每个文件的判定结果（`[OK] ...`） |

退出码：`0` 无违规 / `1` 存在（未修复的）违规 / `2` 路径无效。

`-Fix` 对 `.ps1` 补 UTF-8 BOM；对 `.bat`/`.cmd` 统一 CRLF、去掉 BOM、把 `chcp` 挪到任何中文行之前；
对 `.py`/`.md`/`.json` 等统一成 UTF-8 无 BOM。纯 ASCII 文件不会被刷出无意义 diff。

手工兜底（仅用于已确认是 UTF-8 的 `.ps1`，补 BOM）：

```powershell
$p = '.\tools\foo.ps1'
[IO.File]::WriteAllText($p, [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), [Text.UTF8Encoding]::new($true))
```

反过来，**不要**用 `Get-Content` / `ReadAllText` 的默认编码读一个 GBK 文件再写回 UTF-8：
解码阶段插入的替换字符会永久损坏内容。先确定源编码（`-SourceEncoding Ansi`）再改写。

### 接入 CI / pre-commit

本仓库自身就跑着同一个门禁（[.github/workflows/encoding-gate.yml](.github/workflows/encoding-gate.yml)），
你可以直接照搬：

```yaml
name: encoding-gate
on: [push, pull_request]
jobs:
  script-encoding:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check script encodings
        shell: pwsh
        run: ./skills/windows-cjk-script-encoding/scripts/normalize-script-encoding.ps1 -Path . -Recurse -Check
```

本机 pre-commit 钩子（`.git/hooks/pre-commit`）：

```sh
#!/bin/sh
pwsh -NoProfile -File ./skills/windows-cjk-script-encoding/scripts/normalize-script-encoding.ps1 -Path . -Recurse -Check || {
  echo "编码门禁未通过：请运行 -Fix 后再提交" >&2
  exit 1
}
```

### 实测矩阵

<details>
<summary>展开：实测环境与完整矩阵（Windows 11 / ACP=936 / PS 5.1 与 7.6）</summary>

实测环境：Windows 11 build 26200，系统 ACP/OEMCP = 936（简体中文），Windows PowerShell 5.1.26100，
PowerShell 7.6.5。复现方法与 Git 侧注意事项见
[references/encoding-matrix.md](skills/windows-cjk-script-encoding/references/encoding-matrix.md)。

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

</details>

### 常见症状对照

<details>
<summary>展开：症状 → 处置</summary>

| 你看到的 | 处置 |
| --- | --- |
| `涓枃杈撳嚭`、`涓枃娴嬭瘯` | 典型 UTF-8 被当 GBK 读：`.ps1` 补 BOM，或给批处理补 `chcp 65001` |
| `锟斤拷` | 编码转换中产生了替换字符，通常已经损坏；用 `-SourceEncoding` 指定源编码重试 |
| `'xxx' 不是内部或外部命令` | 批处理行尾不是 CRLF，或文件是 UTF-16 → `-Path x.bat -Fix` |
| 只在 PowerShell 5.1 出错 | 文件缺 BOM → `-Path . -Recurse -Fix` |
| 只在 PowerShell 7 出错 | 文件是 GBK/ANSI → 同上；7.x 默认按 UTF-8 读源码 |
| 输出到文件就乱、屏幕上正常 | 输出侧编码问题：`[Console]::OutputEncoding` / `PYTHONIOENCODING=utf-8` |
| 前一条命令正常、后一条乱 | 批处理里的 `chcp` 改了共享控制台代码页，需在每个入口显式声明编码 |

每次改完脚本，用目标宿主实跑一遍再交付：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\foo.ps1   # 5.1，必测
pwsh.exe       -NoProfile -ExecutionPolicy Bypass -File .\foo.ps1   # 7.x
```

</details>

## 开发与门禁

```powershell
# 本仓库自查（CI 跑的就是这一条）
pwsh -NoProfile -File .\skills\windows-cjk-script-encoding\scripts\normalize-script-encoding.ps1 -Path . -Recurse -Check

# skill 结构校验
python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\quick_validate.py" .\skills\windows-cjk-script-encoding
```

## 免责声明

本仓库的 skill 与脚本按**"原样（AS IS）"**提供，用于提升日常工作效率。它们是在
Windows 11 / 中文区域（ACP=936）/ PowerShell 5.1 与 7.6 环境下实测通过的，但不同 Windows 版本、
区域设置、终端（Windows Terminal / ConHost / CI Runner）与第三方工具仍可能有差异：
**用于生产流程或关键业务前，请先在你自己的环境里验证。**

## 许可证

本项目采用 **MIT License**，完整条款见 [LICENSE](LICENSE)。

任何人都可以自由地使用、复制、修改、合并、发布、分发、再许可甚至出售本项目的副本，唯一要求是
保留版权声明与许可声明；软件按"原样"提供，不附带任何形式的担保。
如果你只是想把这里的编码规则或检查脚本用到自己的项目里，直接用即可，不必事先询问。
