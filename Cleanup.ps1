# Cleanup.ps1
# Run as Administrator

$ErrorActionPreference = "Continue"

Write-Host "`nStarting Student Kiosk Cleanup..." -ForegroundColor Cyan

# 1. Remove scheduled task
$TaskName = "StudentCalibrateLauncher"
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Scheduled task removed." -ForegroundColor Green
}

# 2. Remove kiosk files
$KioskFolder = "C:\ProgramData\StudentCalibrateKiosk"
if (Test-Path $KioskFolder) {
    Remove-Item -LiteralPath $KioskFolder -Recurse -Force
    Write-Host "Kiosk launcher files removed." -ForegroundColor Green
}

# 3. Remove installer
$InstallerPath = "C:\CALIBRATE-Setup.exe"
if (Test-Path $InstallerPath) {
    Remove-Item -LiteralPath $InstallerPath -Force
    Write-Host "Temporary installer removed." -ForegroundColor Green
}

# 4. Remove student account + profile
$Student = Get-LocalUser -Name "student" -ErrorAction SilentlyContinue
if ($Student) {
    Remove-LocalUser -Name "student" -ErrorAction SilentlyContinue
    Write-Host "Student account removed." -ForegroundColor Green
}

$ProfilePath = "C:\Users\student"
if (Test-Path $ProfilePath) {
    Remove-Item -LiteralPath $ProfilePath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Student profile folder removed." -ForegroundColor Green
}

Write-Host "`nCleanup completed. Restart Windows if needed." -ForegroundColor Cyan