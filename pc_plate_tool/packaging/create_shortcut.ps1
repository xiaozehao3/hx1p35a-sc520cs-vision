<#
为车牌识别上位机创建桌面快捷方式。

用法：
  powershell -NoProfile -ExecutionPolicy Bypass -File create_shortcut.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File create_shortcut.ps1 -AppDir "D:\某处\车牌识别上位机"

默认在脚本所在目录查找 PlateRecognizer.exe，并为其在桌面创建快捷方式。
注意：本文件必须保存为「UTF-8 带 BOM」，否则 Windows PowerShell 5.1 会把中文读成乱码。
#>
param(
    [string]$AppDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# 一律转换成绝对路径：快捷方式里存的是绝对路径，相对路径会随调用方的当前目录拼错。
if (Test-Path -LiteralPath $AppDir) {
    $AppDir = (Resolve-Path -LiteralPath $AppDir).Path
} else {
    Write-Host "[失败] 目录不存在：$AppDir" -ForegroundColor Red
    exit 1
}

$exe = Join-Path $AppDir 'PlateRecognizer.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host "[失败] 未在该目录找到 PlateRecognizer.exe：" -ForegroundColor Red
    Write-Host "       $AppDir" -ForegroundColor Red
    Write-Host "        请把本脚本与 PlateRecognizer.exe 放在同一个文件夹里再运行。" -ForegroundColor Yellow
    exit 1
}

$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop '车牌识别上位机.lnk'

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = $exe
$lnk.WorkingDirectory = $AppDir
$lnk.IconLocation = "$exe,0"
$lnk.Description = '车牌识别上位机（图片导入 / 车牌检测 / 字符识别）'
$lnk.Save()

if (Test-Path -LiteralPath $lnkPath) {
    Write-Host "[完成] 已在桌面创建快捷方式：" -ForegroundColor Green
    Write-Host "       $lnkPath"
    Write-Host "       双击桌面上的「车牌识别上位机」即可打开（无需联网、无需 Python）。"
} else {
    Write-Host "[失败] 未能写入桌面快捷方式，请检查桌面目录权限。" -ForegroundColor Red
    exit 1
}
