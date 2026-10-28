# 02-InstallApp.ps1
# Run as Administrator

$ErrorActionPreference = "Stop"

$InstallerSource = Join-Path $PSScriptRoot "CALIBRATE-PREPROD+Setup+1.0.3.exe"
$InstallerDestination = "C:\CALIBRATE-Setup.exe"

if (-not (Test-Path $InstallerSource -PathType Leaf)) {
    throw "Installer not found: $InstallerSource"
}

Copy-Item -LiteralPath $InstallerSource -Destination $InstallerDestination -Force

# Allow standard users to read and execute
& icacls.exe $InstallerDestination /grant "*S-1-5-32-545:RX" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set installer permissions."
}

Write-Host "Installer copied to: $InstallerDestination" -ForegroundColor Green