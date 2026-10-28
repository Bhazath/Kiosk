
# 04-WindowsRestrictions.ps1
# Run as Administrator.
# Applies Windows restrictions to the student account only.
# Does not replace the Windows shell or create a duplicate app launcher.
# If the student profile does not exist, log in as student once and rerun.

$ErrorActionPreference = "Stop"

$StudentName = "student"
$ProfilePath = "C:\Users\$StudentName"
$HiveName = "StudentRestrictionsTemp"
$HivePath = "HKU\$HiveName"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Windows Restrictions for Student User" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Confirm administrator privileges.
$Principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Please run PowerShell as Administrator."
}

# Confirm the student account exists.
$Student = Get-LocalUser -Name $StudentName -ErrorAction SilentlyContinue

if (-not $Student) {
    throw "The local account '$StudentName' does not exist. Run 01-CreateStudent.ps1 first."
}

# Find the student's actual Windows profile.
$StudentProfileInfo = Get-CimInstance Win32_UserProfile |
    Where-Object {
        $_.SID -eq $Student.SID.Value -and -not $_.Special
    } |
    Select-Object -First 1

if (-not $StudentProfileInfo) {
    throw "Student profile not found. Sign in to Windows once as '$StudentName', sign out, then rerun this script."
}

$ProfilePath = $StudentProfileInfo.LocalPath
$NtUserDat = Join-Path $ProfilePath "NTUSER.DAT"

if (-not (Test-Path -LiteralPath $NtUserDat -PathType Leaf)) {
    throw "Student registry file not found: $NtUserDat"
}

# Do not load a second copy if the student is currently signed in.
if ($StudentProfileInfo.Loaded) {
    throw "The student profile is currently loaded. Sign out as student and rerun this script."
}

# Ensure the temporary hive name is not already in use.
& reg.exe query $HivePath *> $null
if ($LASTEXITCODE -eq 0) {
    throw "Temporary registry hive $HivePath is already loaded. Resolve that before continuing."
}

Write-Host "Student profile: $ProfilePath" -ForegroundColor Green
Write-Host "Loading student registry hive..." -ForegroundColor Yellow

$LoadResult = & reg.exe load $HivePath $NtUserDat 2>&1

if ($LASTEXITCODE -ne 0) {
    throw "Failed to load student registry hive: $LoadResult"
}

try {
    $ExplorerPolicy = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $SystemPolicy   = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    $AdvancedKey    = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $SearchKey      = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Search"

    # Create policy keys if missing.
    foreach ($Key in @(
        $ExplorerPolicy,
        $SystemPolicy,
        $AdvancedKey,
        $SearchKey
    )) {
        & reg.exe add $Key /f | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create registry key: $Key"
        }
    }

    Write-Host "Applying student restrictions..." -ForegroundColor Yellow

    # Restrict selected Explorer and Start menu features for student.
    # These settings do not prevent every possible way to launch programs.
    $ExplorerSettings = @{
        NoRun                      = 1  # Disable the Run command.
        NoFind                     = 1  # Disable the legacy Find/Search command.
        NoViewContextMenu          = 1  # Disable Explorer desktop/file context menus.
        NoControlPanel             = 1  # Hide Control Panel entry points.
        NoSetTaskbar               = 1  # Restrict taskbar/Start menu settings.
        NoChangeStartMenu          = 1  # Prevent Start menu customization.
        NoStartMenuPinnedList      = 1  # Hide the pinned-programs list.
        NoStartMenuMFUprogramsList = 1  # Hide frequently used programs.
        NoStartMenuSubFolders      = 1  # Hide Start menu subfolders.
        NoWinKeys                  = 1  # Disable Windows-key shortcuts.
        NoTaskSwitches             = 1  # Disable Alt+Tab task switching.
        NoDesktop                  = 1  # Hide desktop icons.
    }

    foreach ($Item in $ExplorerSettings.GetEnumerator()) {
        & reg.exe add $ExplorerPolicy `
            /v $Item.Key /t REG_DWORD /d $Item.Value /f | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to apply Explorer policy: $($Item.Key)"
        }
    }

    # Restrict Task Manager and Control Panel for student.
    & reg.exe add $SystemPolicy /v DisableTaskMgr /t REG_DWORD /d 1 /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to disable Task Manager."
    }

    & reg.exe add $SystemPolicy /v NoControlPanel /t REG_DWORD /d 1 /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to restrict Control Panel."
    }

    # Hide selected taskbar buttons/search entry points.
    # Windows may ignore some values depending on its version.
    $AdvancedSettings = @{
        ShowTaskViewButton = 0
        TaskbarDa          = 0
        TaskbarMn          = 0
        TaskbarSearch      = 0
    }

    foreach ($Item in $AdvancedSettings.GetEnumerator()) {
        & reg.exe add $AdvancedKey `
            /v $Item.Key /t REG_DWORD /d $Item.Value /f | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to apply taskbar setting: $($Item.Key)"
        }
    }

    # Hide the Windows taskbar search box where supported.
    & reg.exe add $SearchKey /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to configure taskbar search."
    }

    Write-Host "Student restrictions applied successfully." -ForegroundColor Green
}
finally {
    # Always unload the temporary registry hive.
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    $UnloadResult = & reg.exe unload $HivePath 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not unload registry hive $HivePath. Details: $UnloadResult"
    }
    else {
        Write-Host "Student registry hive unloaded." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "COMPLETED." -ForegroundColor Green
Write-Host "Restrictions apply to the student profile only."
Write-Host "CALIBRATE launching remains managed by 03-LaunchApp.ps1."
Write-Host "Sign in as student to test the restrictions."
