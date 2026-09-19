# Codex Skills

自用的 Codex skill 集合，按 `skills/<skill-name>/` 组织，每个目录都是一个可独立安装的 skill：
复制到 `%USERPROFILE%\.codex\skills\` 下即可被 Codex 自动发现。

## 包含的 skill

| Skill | 作用 |
| --- | --- |
| [windows-cjk-script-encoding](skills/windows-cjk-script-encoding/SKILL.md) | 让 `.ps1` / `.psm1` / `.bat` / `.cmd` / `.py` 里的中文不再乱码：编码硬性规则、双宿主实测矩阵，以及可挂 CI 的 `-Check` / `-Fix` 编码门禁脚本 |

## 安装

```powershell
# 安装全部 skill
Copy-Item .\skills\* "$env:USERPROFILE\.codex\skills\" -Recurse -Force

# 只安装某一个
Copy-Item .\skills\windows-cjk-script-encoding "$env:USERPROFILE\.codex\skills\" -Recurse -Force
```

## 编码门禁

`windows-cjk-script-encoding` 自带检查脚本，有违规时退出码为 1，可直接挂到 CI 或 pre-commit：

```powershell
pwsh -NoProfile -File .\skills\windows-cjk-script-encoding\scripts\normalize-script-encoding.ps1 -Path . -Recurse -Check
pwsh -NoProfile -File .\skills\windows-cjk-script-encoding\scripts\normalize-script-encoding.ps1 -Path .\scripts -Recurse -Fix
```
