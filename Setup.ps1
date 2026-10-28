# Setup.ps1
# Run as Administrator

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

$Principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Please run PowerShell as Administrator."
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

    try {
        & $Path
    }
    catch {
        throw "Setup stopped at ${Module}: $($_.Exception.Message)"
    }
}

Write-Host "`nSetup completed successfully." -ForegroundColor Green
Write-Host "Please restart the computer and login as student to test."