# 02-InstallApp.ps1
# Copies the CALIBRATE installer from the Kiosk folder to C:\.
# Grants standard users permission to read and execute the installer.

$ErrorActionPreference = "Stop"

$InstallerSource = Join-Path $PSScriptRoot "CALIBRATE-PREPROD+Setup+1.0.3.exe"
$InstallerDestination = "C:\CALIBRATE-Setup.exe"

if (-not (Test-Path -LiteralPath $InstallerSource -PathType Leaf)) {
    throw "Installer not found: $InstallerSource"
}

Copy-Item -LiteralPath $InstallerSource `
    -Destination $InstallerDestination `
    -Force

& icacls.exe $InstallerDestination /grant "*S-1-5-32-545:RX" | Out-Null

if ($LASTEXITCODE -ne 0) {
    throw "Failed to set installer permissions."
}

Write-Host "Installer copied successfully: $InstallerDestination" -ForegroundColor Green