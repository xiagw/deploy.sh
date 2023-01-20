# Get-ExecutionPolicy -List #查看当前的执行策略
# Set-ExecutionPolicy -Scope CurrentUser RemoteSigned #设置执行策略为要求远程脚本签名，范围为当前用户
# irm https://github.com/xiagw/deploy.sh/raw/main/bin/install.ssh.ps1 | iex
# irm https://gitee.com/xiagw/deploy.sh/raw/main/bin/install.ssh.ps1 | iex

Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'

# Install the OpenSSH Client
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Install the OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start the sshd service
Start-Service sshd

# OPTIONAL but recommended:
Set-Service -Name sshd -StartupType 'Automatic'

# Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
}
## 默认 shell 设置为 powershell.exe：
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
## comment authorized_keys
(Get-Content -Path C:\ProgramData\ssh\sshd_config -Raw) -replace 'Match Group administrators','#Match Group administrators' | Set-Content -Path C:\ProgramData\ssh\sshd_config
(Get-Content -Path C:\ProgramData\ssh\sshd_config -Raw) -replace 'AuthorizedKeysFile __PROGRAMDATA__','#AuthorizedKeysFile __PROGRAMDATA__' | Set-Content -Path C:\ProgramData\ssh\sshd_config

Restart-Service sshd

# By default the ssh-agent service is disabled. Allow it to be manually started for the next step to work.
# Make sure you're running as an Administrator.
# Get-Service ssh-agent | Set-Service -StartupType Manual
# Start the service
# Start-Service ssh-agent
# This should return a status of Running
# Get-Service ssh-agent
# Now load your key files into ssh-agent
# ssh-add ~\.ssh\id_ed25519

# Make sure that the .ssh directory exists in your server's user account home folder
# ssh username@domain1@contoso.com mkdir C:\Users\username\.ssh\
# Use scp to copy the public key file generated previously on your client to the authorized_keys file on your server
# scp C:\Users\username\.ssh\id_ed25519.pub user1@domain1@contoso.com:C:\Users\username\.ssh\authorized_keys

New-Item -Path $HOME\.ssh -Type Directory -Force
(Invoke-WebRequest 'https://api.github.com/users/xiagw/keys' | ConvertFrom-Json).key | Set-Content -Path $HOME\.ssh\authorized_keys
# New-Item -Path "C:\ProgramData\ssh\administrators_authorized_keys" -Type File -Force
# icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
# echo '<pub_key>' >"C:\ProgramData\ssh\administrators_authorized_keys"


# $env:HTTP_PROXY="http://192.168.1.154:1080"
# $env:HTTPS_PROXY="http://192.168.1.154:1080"

## powershell 7
# winget install --id Microsoft.Powershell --source winget

## oh my posh
# winget install JanDeDobbeleer.OhMyPosh --source winget
# scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))
New-Item -Path $PROFILE -Type File -Force
echo 'oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/ys.omp.json" | Invoke-Expression' >$PROFILE

## Not Admin console
# iwr -useb get.scoop.sh | iex

# winget settings

## windows server 2022 install Windows Terminal
# https://4sysops.com/archives/install-windows-terminal-without-the-store-on-windows-server/

## enable/disable proxy
# Set-ItemProperty -Path "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" ProxyEnable -value 0
# Set-ItemProperty -Path "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" ProxyEnable -value 1