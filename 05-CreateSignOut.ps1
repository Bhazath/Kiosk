
# 05-CreateSignOut.ps1
# Run as Administrator.
# Creates a Sign out shortcut for new Windows user profiles.
# Does not sign out automatically; it only creates the shortcut.

$ErrorActionPreference = "Stop"

# Verify administrator privileges.
$Principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Please run PowerShell as Administrator."
}

# Default profile desktop: shortcut appears on desktops of newly created profiles.
$DesktopPath = Join-Path $env:SystemDrive "Users\Default\Desktop"
$ShortcutPath = Join-Path $DesktopPath "Sign out.lnk"

if (-not (Test-Path -LiteralPath "$env:WINDIR\System32\shutdown.exe")) {
    throw "shutdown.exe was not found."
}

New-Item -Path $DesktopPath -ItemType Directory -Force | Out-Null

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)

$Shortcut.TargetPath = "$env:WINDIR\System32\shutdown.exe"
$Shortcut.Arguments = "/l"
$Shortcut.WorkingDirectory = "$env:WINDIR\System32"
$Shortcut.Description = "Sign out of the current Windows account"
$Shortcut.Save()

if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
    throw "Failed to create the sign-out shortcut."
}

Write-Host "Sign-out shortcut created: $ShortcutPath" -ForegroundColor Green
Write-Host "This applies to new profiles; existing student profiles may need the shortcut copied separately."
