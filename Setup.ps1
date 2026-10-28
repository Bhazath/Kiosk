
# Setup.ps1
# Runs from any folder and requests Administrator permission.

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

$Principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Start-Process powershell.exe `
        -Verb RunAs `
        -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`""
        )
    exit
}

$Modules = @(
    "01-CreateStudent.ps1",
    "02-InstallApp.ps1",
    "03-LaunchApp.ps1",
    "04-WindowsRestrictions.ps1",
    "05-CreateSignOut.ps1"
)

foreach ($Module in $Modules) {
    $Path = Join-Path $Root $Module

    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Missing module: $Path"
    }

    Write-Host "`nRunning $Module..." -ForegroundColor Cyan
    & $Path
}

Write-Host "`nSetup completed successfully." -ForegroundColor Green
Write-Host "Restart the computer and test the student account."
