<#
  install.ps1 — 把 mkxp-z 兼容加载器装进指定的 RGSS2(VX) 游戏目录。

  用法：
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -GameDir "D:\Games\SomeVXGame"

  它只做两件事（不会碰游戏文件）：
    1) 复制 mkxp_loader.rb 到游戏目录
    2) 写入 mkxp.json（若已存在则先备份为 mkxp.json.bak）

  前置条件：游戏目录里应已有 mkxp-z 的可执行文件与 Data/Scripts.rvdata；
  并且请确认你拥有该游戏的正版授权。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$GameDir,
  [string]$WindowTitle = "",
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path -LiteralPath $GameDir)) { throw "GameDir not found: $GameDir" }
$GameDir = (Resolve-Path -LiteralPath $GameDir).Path

$scripts = Join-Path $GameDir "Data\Scripts.rvdata"
if (-not (Test-Path -LiteralPath $scripts)) {
  Write-Warning "Data\Scripts.rvdata not found in $GameDir — is this really an RGSS2/VX game folder?"
}

# 1) loader
Copy-Item -LiteralPath (Join-Path $here "mkxp_loader.rb") -Destination (Join-Path $GameDir "mkxp_loader.rb") -Force
Write-Host "[ok] mkxp_loader.rb -> $GameDir"

# 2) config
$cfgPath = Join-Path $GameDir "mkxp.json"
$cfg = Get-Content -LiteralPath (Join-Path $here "mkxp.json") -Raw
if ($WindowTitle -ne "") {
  $cfg = $cfg -replace '"windowTitle"\s*:\s*"[^"]*"', ('"windowTitle": "' + $WindowTitle + '"')
}
if (Test-Path -LiteralPath $cfgPath) {
  if (-not $Force) {
    Copy-Item -LiteralPath $cfgPath -Destination ($cfgPath + ".bak") -Force
    Write-Host "[ok] existing mkxp.json backed up -> mkxp.json.bak"
  }
}
[System.IO.File]::WriteAllText($cfgPath, $cfg, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[ok] mkxp.json -> $cfgPath"

Write-Host ""
Write-Host "Done. Now run mkxp-z from the game folder."
Write-Host "Log: dsh_log.txt   (Shift = A key / F12 = back to title / F1 = mkxp settings / F2 = fps)"
