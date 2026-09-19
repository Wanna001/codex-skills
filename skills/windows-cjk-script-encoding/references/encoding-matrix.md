# 编码实测矩阵与排查手册

实测环境（2026-09-19）：Windows 11 build 26200，系统 ACP/OEMCP = 936（简体中文），
Windows PowerShell 5.1.26100.9168（`powershell.exe`），PowerShell 7.6.5（`pwsh.exe`）。

复现方式：把同一段脚本分别以不同编码写入临时文件，用 `Start-Process -RedirectStandardOutput`
把 stdout 落到文件，再按字节读取（避免父进程的编码把结论污染掉），最后按 UTF-8 / GBK 两种方式解码比对。

## PowerShell 脚本（`-File` 方式执行）

脚本内容：`$msg = "中文输出 ok"`，期望输出 `中文输出 ok`，`$msg.Length` 应为 7。

| `.ps1` 存储编码 | `powershell.exe`（5.1） | `pwsh.exe`（7.x） |
| --- | --- | --- |
| UTF-8 无 BOM（多数工具默认） | **乱码** `涓枃杈撳嚭 ok`，长度 9 | 正常 |
| UTF-8 with BOM | 正常 | 正常 |
| UTF-16LE（BOM） | 正常 | 正常 |
| GBK / ANSI(936) | 正常 | **乱码** `������� ok`，长度 10 |

结论：**UTF-8 with BOM 是唯一在 5.1 与 7.x 上同时正确的选择**（UTF-16LE 也可以，但对 diff、Git、
工具链不友好）。UTF-8 无 BOM 是 5.1 上中文乱码的头号原因；GBK 是 7.x 上的翻车方式。

纯 ASCII 的 `.ps1` 不受影响：三种编码下字节完全一致，所以门禁默认只对含非 ASCII 的文件强制 BOM
（`-StrictBom` 可要求一律带 BOM）。这样既有防护，又不会给存量纯 ASCII 脚本刷出无意义 diff；
一旦有人往里面写中文，检查立刻变红。

注意长度变化这一点：5.1 把 UTF-8 字节按 936 解码后，每个中文字符变成 1~2 个字符，
于是 `$msg.Length`、`-eq`、`-match`、`Substring` 都在错误的前提下运行，这就是"中文一进来命令就跑不了"
而不只是"显示难看"的原因。

## 批处理（cmd.exe）

脚本内容：`echo 中文测试` + `set MSG=中文变量` + `echo %MSG%`。

| 文件编码 | 行尾 | chcp | 结果 |
| --- | --- | --- | --- |
| UTF-8 无 BOM | CRLF | 无 | 控制台（936）显示 `涓枃娴嬭瘯 / 涓枃鍙橀噺` |
| UTF-8 无 BOM | CRLF | 首部 `chcp 65001>nul` | 正常 |
| UTF-8 with BOM | CRLF | 有 / 无 | 本机正常（BOM 被容忍），但旧版 cmd 会把它当命令内容，仍不建议 |
| GBK / ANSI(936) | CRLF | 控制台 936 | 正常 |
| GBK / ANSI(936) | CRLF | 控制台 65001 | 乱码 `锟斤拷...` |
| UTF-8 无 BOM | **LF only** | 任意 | `'xxx' 不是内部或外部命令`，`goto`/标签失效 |
| UTF-16LE | CRLF | 任意 | 直接无法解析（`'﻿@' 不是内部或外部命令`） |

细节：`chcp 65001` 写在中文行之后时，本机实测**仍然可用**（cmd 逐行按字节偏移重读文件），
但这是脆弱行为，不同 Windows 版本对"中途换代码页"的处理并不一致，所以规则仍是把 `chcp` 放在最前面。
批处理里的 `echo` 输出的是"当前代码页字节"，控制台按自己的代码页渲染，因此文件编码与控制台代码页
必须成套匹配（UTF-8 ↔ 65001，GBK ↔ 936）。

## 控制台与写文件默认值（实测）

PowerShell：

| 宿主 | `[Console]::OutputEncoding` | `[Console]::InputEncoding` | `$OutputEncoding` | `[Text.Encoding]::Default` |
| --- | --- | --- | --- | --- |
| PS 5.1 | utf-8（跟随控制台） | gb2312 | **us-ascii** | gb2312(936) |
| PS 7.6 | utf-8 | gb2312 | utf-8 | utf-8 |

写文件默认值：

| 命令 | 结果字节 |
| --- | --- |
| PS 5.1 `Set-Content -Value '中文'` | `D6 D0 CE C4`（GBK，无 BOM） |
| PS 5.1 `Set-Content -Encoding UTF8 -Value '中文'` | `EF BB BF ...`（UTF-8 **带** BOM） |
| PS 7 `Set-Content -Value '中文'` | `E4 B8 AD E6 96 87`（UTF-8 无 BOM） |
| PS 7 `Set-Content -Encoding utf8BOM -Value '中文'` | UTF-8 带 BOM |

Python 3.12.14：`sys.stdout.encoding = gbk`，`locale.getpreferredencoding(False) = cp936`；
`open(path, 'w')` 写出的中文是 GBK 字节（`D6 D0 CE C4`）；加 `-X utf8` 或 `PYTHONUTF8=1` 后为 UTF-8。
从 PowerShell 调 Python 时若子进程 stdout 被重定向，编码仍取 locale，所以显式给
`PYTHONIOENCODING=utf-8` 最省事。

## 控制台代码页是"共享"的

实测发现：PS 5.1 的 stdout 编码跟随**控制台代码页**（不是固定 UTF-8），而 `chcp` 改的是整个控制台
的状态。因此在 PowerShell 会话里调用一个含 `chcp 936` / `chcp 65001` 的批处理，会顺手把当前控制台
的代码页改掉，之后同一会话里所有命令的输出编码都跟着变——日志采集器、CI 输出解析按固定编码解码时，
就会出现"前一条命令好好的，后一条全乱"的现象。

自保做法：脚本自己显式声明代码页（本 skill 的批处理策略已保证），长时间运行的采集端显式设置
`[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)`，不要依赖"控制台当前恰好是什么代码页"。
排查时先确认乱码发生在文件字节、控制台渲染，还是采集端解码——三者的修复手段不同。

## 判定与修复

自动判定顺序（`scripts/normalize-script-encoding.ps1` 采用）：

1. `EF BB BF` → UTF-8 with BOM；`FF FE` → UTF-16LE；`FE FF` → UTF-16BE。
2. 无 BOM 时做**严格** UTF-8 解码，通过即视为 UTF-8（无 BOM）。
3. 失败则按系统 ACP（本机 936）解码。

第 2 步的已知例外：极少数 GBK 字节序列恰好也是合法 UTF-8（例如部分"生僻字 + ASCII"组合），
会被误判为 UTF-8 并把内容带坏。遇到时用 `-SourceEncoding Ansi` 强制指定源编码再修。

**不要**用 `Get-Content` / `[IO.File]::ReadAllText` 的默认编码读 GBK 文件再回写 UTF-8：
解码阶段产生的 U+FFFD 替换字符会永久损坏内容。要么先确定源编码，要么直接用该脚本修。

## 验证清单（交付前）

```powershell
# 1) BOM 字节：239,187,191 = EF BB BF
$b = [IO.File]::ReadAllBytes('.\tools\foo.ps1'); ($b[0..2] -join ',')

# 2) 双宿主实跑（只跑 pwsh 会漏掉最常见的 5.1 乱码）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\foo.ps1
pwsh.exe       -NoProfile -ExecutionPolicy Bypass -File .\tools\foo.ps1

# 3) 输出是否真的是中文：落到文件后按 UTF-8 读回，比对期望字符串
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\foo.ps1
if ("$out" -notmatch '中文') { throw "输出不是中文：$out" }

# 4) 全仓库体检（可挂 CI / pre-commit，违规退出码 1）
pwsh -NoProfile -File scripts/normalize-script-encoding.ps1 -Path . -Recurse -Check
```

## Git 侧注意事项

- BOM 属于文件内容（blob），会被 Git 原样保存并随 clone 分发，所以"本地修好、队友乱码"不会发生；
  真正会出问题的是用 `.gitattributes` 的 `working-tree-encoding` 去折腾编码——它不支持 UTF-8 BOM，
  而且会引入额外的 diff/合并风险，不要用它处理 `.ps1`。
- 需要固定行尾时用 `.gitattributes` 的 `*.ps1 text eol=crlf` / `*.bat text eol=crlf`（批处理必须 CRLF）。
- 把 `-Check` 挂进 pre-commit 或 CI 是唯一能防止回归的办法：乱码问题一旦再次由"新工具写出 UTF-8 无 BOM"
  引入，只有编码门禁能挡住。
