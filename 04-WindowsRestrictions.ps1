
# 04-WindowsRestrictions.ps1
# Run from Setup.ps1 as Administrator

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Windows Restrictions for Student User" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Check administrator privileges
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Run Setup.ps1 as Administrator."
}

# 2. Check student account
$Student = "student"
$StudentAccount = Get-LocalUser -Name $Student -ErrorAction SilentlyContinue

if (-not $StudentAccount) {
    throw "Student account does not exist. Run 01-CreateStudent.ps1 first."
}

$StudentSid = $StudentAccount.SID.Value
$Profile = Get-CimInstance Win32_UserProfile |
    Where-Object { $_.SID -eq $StudentSid }

$ProfilePath = Join-Path $env:SystemDrive "Users\$Student"

if ($Profile -and $Profile.LocalPath) {
    $ProfilePath = $Profile.LocalPath
}

$NtUserDat = Join-Path $ProfilePath "NTUSER.DAT"

# 3. Create profile if missing
if (-not (Test-Path $NtUserDat)) {
    Write-Host "Creating student profile..." -ForegroundColor Yellow

    if (-not ("StudentProfileNative" -as [type])) {
        Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class StudentProfileNative
{
    [DllImport("userenv.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int CreateProfile(
        string pszUserSid,
        string pszUserName,
        StringBuilder pszProfilePath,
        uint cchProfilePath
    );
}
"@
    }

    $Buffer = New-Object System.Text.StringBuilder 260
    $Result = [StudentProfileNative]::CreateProfile(
        $StudentSid, $Student, $Buffer, [uint32]$Buffer.Capacity
    )

    if ($Result -ne 0 -and -not (Test-Path $NtUserDat)) {
        throw ("Windows could not create the student profile. HRESULT: 0x{0:X8}" -f ($Result -band 0xFFFFFFFF))
    }

    if ($Buffer.Length -gt 0) {
        $ProfilePath = $Buffer.ToString()
    }

    $NtUserDat = Join-Path $ProfilePath "NTUSER.DAT"
}

if (-not (Test-Path $NtUserDat)) {
    throw "Student NTUSER.DAT not found at '$NtUserDat'."
}

# 4. Check whether student profile is currently loaded
$Profile = Get-CimInstance Win32_UserProfile |
    Where-Object { $_.SID -eq $StudentSid }

if ($Profile -and $Profile.Loaded) {
    throw "Student profile is currently loaded. Sign out student and rerun Setup.ps1."
}

$HiveName = "StudentRestrictionsTemp"
$HivePath = "Registry::HKEY_USERS\$HiveName"

if (Test-Path $HivePath) {
    throw "Temporary registry hive HKU\$HiveName already exists. Restart Windows and retry."
}

# 5. Load student registry hive
Write-Host "Loading student registry..." -ForegroundColor Yellow

& reg.exe load "HKU\$HiveName" "$NtUserDat"

if ($LASTEXITCODE -ne 0) {
    throw "Failed to load NTUSER.DAT. Ensure the student profile is not in use, then retry."
}

try {
    $UserRoot = "Registry::HKEY_USERS\$HiveName"

    # 6. Explorer restrictions
    $ExplorerPath = "$UserRoot\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    New-Item -Path $ExplorerPath -Force | Out-Null

    $ExplorerSettings = @{
        NoRun                      = 1
        NoFind                     = 1
        NoViewContextMenu          = 1
        NoControlPanel             = 1
        NoSetTaskbar               = 1
        NoChangeStartMenu          = 1
        NoStartMenuPinnedList      = 1
        NoStartMenuMFUprogramsList = 1
        NoStartMenuSubFolders      = 1
        NoWinKeys                  = 1
        NoTaskSwitches             = 1
        NoDesktop                  = 1
    }

    foreach ($Setting in $ExplorerSettings.GetEnumerator()) {
        New-ItemProperty -Path $ExplorerPath `
            -Name $Setting.Key -Value $Setting.Value `
            -PropertyType DWord -Force | Out-Null
    }

    # 7. System restrictions
    $SystemPath = "$UserRoot\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    New-Item -Path $SystemPath -Force | Out-Null

    New-ItemProperty -Path $SystemPath `
        -Name "DisableTaskMgr" -Value 1 `
        -PropertyType DWord -Force | Out-Null

    New-ItemProperty -Path $SystemPath `
        -Name "NoControlPanel" -Value 1 `
        -PropertyType DWord -Force | Out-Null

    Write-Host "Main student restrictions applied." -ForegroundColor Green

    # 8. Optional taskbar settings
    $AdvancedPath = "$UserRoot\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    try {
        if (Test-Path $AdvancedPath) {
            $AdvancedSettings = @{
                ShowTaskViewButton = 0
                TaskbarDa          = 0
                TaskbarMn          = 0
                TaskbarSearch      = 0
            }

            foreach ($Setting in $AdvancedSettings.GetEnumerator()) {
                New-ItemProperty -Path $AdvancedPath `
                    -Name $Setting.Key -Value $Setting.Value `
                    -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            }
        } else {
            Write-Warning "Advanced key missing; skipping optional taskbar settings."
        }
    }
    catch {
        Write-Warning "Optional taskbar settings skipped: $($_.Exception.Message)"
    }

    # Search button setting
    try {
        $SearchPath = "$UserRoot\Software\Microsoft\Windows\CurrentVersion\Search"
        New-Item -Path $SearchPath -Force | Out-Null

        New-ItemProperty -Path $SearchPath `
            -Name "SearchboxTaskbarMode" -Value 0 `
            -PropertyType DWord -Force | Out-Null
    }
    catch {
        Write-Warning "Search taskbar setting skipped: $($_.Exception.Message)"
    }
}
finally {
    # 9. Unload registry hive
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    & reg.exe unload "HKU\$HiveName"

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not unload the temporary registry hive. Restart Windows before testing."
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Student restrictions configuration ended" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Sign in as student to test the settings."
Write-Host "Note: These settings do not fully lock down Windows or restrict every application."
