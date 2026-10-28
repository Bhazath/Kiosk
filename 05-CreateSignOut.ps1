# 05-CreateSignOut.ps1
# Run as Administrator

$ErrorActionPreference = "Stop"

$DesktopPath = "C:\Users\Default\Desktop"
$ShortcutPath = Join-Path $DesktopPath "Sign out.lnk"

New-Item -Path $DesktopPath -ItemType Directory -Force | Out-Null

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "$env:WINDIR\System32\shutdown.exe"
$Shortcut.Arguments = "/l"
$Shortcut.WorkingDirectory = "$env:WINDIR\System32"
$Shortcut.Description = "Sign out of the student account"
$Shortcut.Save()

Write-Host "Sign out shortcut created in Default User desktop." -ForegroundColor Green