
$ErrorActionPreference = "Stop"

$Name = "student"
$Password = ConvertTo-SecureString "student" -AsPlainText -Force

$user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue

if (-not $user) {
    New-LocalUser -Name $Name `
        -Password $Password `
        -Description "Student CALIBRATE account" | Out-Null
} else {
    Set-LocalUser -Name $Name -Password $Password
}

Enable-LocalUser -Name $Name
Set-LocalUser -Name $Name -PasswordNeverExpires $true
net.exe user $Name /passwordreq:yes

# Ensure standard-user membership.
try {
    Add-LocalGroupMember -Group "Users" -Member $Name
} catch {
    if (-not (Get-LocalGroupMember -Group "Users" |
        Where-Object { $_.SID.Value -eq (Get-LocalUser $Name).SID.Value })) {
        throw
    }
}

# Ensure the student is not an administrator.
try {
    Remove-LocalGroupMember -Group "Administrators" -Member $Name
} catch {}

Get-LocalUser $Name |
    Select-Object Name, Enabled, PasswordRequired

Write-Host "Student account configured." -ForegroundColor Green
Write-Host "Username: $env:COMPUTERNAME\$Name"
Write-Host "Password: student"
