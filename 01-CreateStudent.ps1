# 01-CreateStudent.ps1
# Creates the student account or enables it without resetting an existing password.
# Ensures student is a standard user, not an administrator.

$ErrorActionPreference = "Stop"

$Name = "student"
$Password = ConvertTo-SecureString "student" -AsPlainText -Force

$user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue

if (-not $user) {
    New-LocalUser -Name $Name `
        -Password $Password `
        -Description "Student CALIBRATE account" `
        -PasswordNeverExpires | Out-Null

    Write-Host "Student account created." -ForegroundColor Green
} else {
    Write-Host "Student account already exists; password unchanged." -ForegroundColor Yellow
}

Enable-LocalUser -Name $Name
Set-LocalUser -Name $Name -PasswordNeverExpires $true

# Ensure the student belongs to the standard Users group.
$StudentSid = (Get-LocalUser -Name $Name).SID.Value
$UsersMembers = Get-LocalGroupMember -Group "Users" -ErrorAction SilentlyContinue

if (-not ($UsersMembers | Where-Object { $_.SID.Value -eq $StudentSid })) {
    Add-LocalGroupMember -Group "Users" -Member $Name
}

# Ensure the student is not a member of Administrators.
$AdminMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue

if ($AdminMembers | Where-Object { $_.SID.Value -eq $StudentSid }) {
    Remove-LocalGroupMember -Group "Administrators" -Member $Name
}

Get-LocalUser -Name $Name |
    Select-Object Name, Enabled, PasswordRequired, PasswordExpires

Write-Host "Student account configured." -ForegroundColor Green
Write-Host "Username: $env:COMPUTERNAME\$Name"
if (-not $user) {
    Write-Host "Initial password: student"
}