## 查看当前的执行策略
# Get-ExecutionPolicy -List
## 设置执行策略为要求远程脚本签名，范围为当前用户
# Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# irm https://github.com/xiagw/deploy.sh/raw/main/bin/win.ssh.ps1 | iex
# irm https://gitee.com/xiagw/deploy.sh/raw/main/bin/win.ssh.ps1 | iex

# Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'
# Install the OpenSSH Client
# Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
# Install the OpenSSH Server
# Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Get-WindowsCapability -online | Where-Object {$_.Name -like "OpenSSH*" -and $_.State -eq "NotPresent"} | Add-WindowsCapability -online

# Start the sshd service
Start-Service sshd

# OPTIONAL but recommended:
Set-Service -Name sshd -StartupType 'Automatic'

# Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
if (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled) {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
} else {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
}

## 默认 shell 设置为 powershell.exe：
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

## comment authorized_keys for administrators
(Get-Content -Path C:\ProgramData\ssh\sshd_config -Raw) -replace 'Match Group administrators','#Match Group administrators' | Set-Content -Path C:\ProgramData\ssh\sshd_config
(Get-Content -Path C:\ProgramData\ssh\sshd_config -Raw) -replace 'AuthorizedKeysFile __PROGRAMDATA__','#AuthorizedKeysFile __PROGRAMDATA__' | Set-Content -Path C:\ProgramData\ssh\sshd_config

Restart-Service sshd

## add $HOME\.ssh\authorized_keys
New-Item -Path "$HOME\.ssh\authorized_keys" -Type File -Force
(Invoke-RestMethod 'https://api.github.com/users/xiagw/keys').key | Add-Content -Path "$HOME\.ssh\authorized_keys"
icacls.exe "$HOME\.ssh\authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
# (Invoke-WebRequest 'https://api.github.com/users/xiagw/keys' | ConvertFrom-Json).key | Add-Content -Path $HOME\.ssh\authorized_keys
New-Item -Path "C:\ProgramData\ssh\administrators_authorized_keys" -Type File -Force
(Invoke-RestMethod 'https://api.github.com/users/xiagw/keys').key | Add-Content -Path "C:\ProgramData\ssh\administrators_authorized_keys"
icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

# By default the ssh-agent service is disabled. Allow it to be manually started for the next step to work.
# Make sure you're running as an Administrator.
# Get-Service ssh-agent | Set-Service -StartupType Manual
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
Get-Service ssh-agent
# Now load your key files into ssh-agent
# ssh-add ~\.ssh\id_ed25519

## install scoop, not Admin console
# irm get.scoop.sh | iex

## oh my posh
if (oh-my-posh.exe --version) {
    Write-Host "oh-my-posh already installed"
} else {
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))
    New-Item -Path $PROFILE -Type File -Force
    Add-Content -Path $PROFILE -Value 'oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/ys.omp.json" | Invoke-Expression'
}
# winget install JanDeDobbeleer.OhMyPosh --source winget
# scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json

# winget settings

## windows server 2022 install Windows Terminal
# https://4sysops.com/archives/install-windows-terminal-without-the-store-on-windows-server/

## enable/disable proxy
# Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" ProxyEnable -value 0
# Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" ProxyEnable -value 1

# $env:HTTP_PROXY="http://192.168.1.154:1080"
# $env:HTTPS_PROXY="http://192.168.1.154:1080"

## install powershell 7
# winget install --id Microsoft.Powershell --source winget

## install Remote Server Administrator
# Get-WindowsCapability -Online -Name 'Rsat.Server*' | Add-WindowsCapability -Online

## windows auto login
# $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
# $DefaultUsername = "{windowsUser.user}"
# $DefaultPassword = "{windowsUser.password}"
# Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -type String
# Set-ItemProperty $RegPath "DefaultUsername" -Value "$DefaultUsername" -type String
# Set-ItemProperty $RegPath "DefaultPassword" -Value "$DefaultPassword" -type String