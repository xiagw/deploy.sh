## 查看当前的执行策略
# Get-ExecutionPolicy -List
## 设置执行策略为要求远程脚本签名，范围为当前用户
# Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

## 在中国大陆
# irm https://gitee.com/xiagw/deploy.sh/raw/main/docs/win.ssh.ps1 | iex
## 不在在中国大陆
# irm https://github.com/xiagw/deploy.sh/raw/main/docs/win.ssh.ps1 | iex

## 激活windows
## https://github.com/massgravel/Microsoft-Activation-Scripts
# irm https://massgrave.dev/get | iex

## 安装openssh
# Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'
Get-WindowsCapability -online | Where-Object {$_.Name -like "OpenSSH*" -and $_.State -eq "NotPresent"} | Add-WindowsCapability -online
## Start the sshd service
Start-Service sshd
## OPTIONAL but recommended:
Set-Service -Name sshd -StartupType 'Automatic'
## Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
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
## restart sshd service
Restart-Service sshd
## 设置authorized_keys
## authoized_keys for normal users
$FileAuthHome = "$HOME\.ssh\authorized_keys"
if (Test-Path $FileAuthHome) {
    Write-Output "File $FileAuthHome exists."
} else {
    New-Item -Path $FileAuthHome -Type File -Force
}
(Invoke-RestMethod 'https://api.github.com/users/xiagw/keys').key | Add-Content -Path $FileAuthHome
# icacls.exe "$FileAuthHome" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
## authoized_keys for admin users
$FileAuthAdmin = "C:\ProgramData\ssh\administrators_authorized_keys"
if (Test-Path $FileAuthAdmin) {
    Write-Output "File $FileAuthAdmin exists."
} else {
    New-Item -Path $FileAuthAdmin -Type File -Force
}
# (Invoke-WebRequest 'https://api.github.com/users/xiagw/keys' | ConvertFrom-Json).key | Add-Content -Path $FileAuthHome
# (Invoke-RestMethod 'https://api.github.com/users/xiagw/keys').key | Add-Content -Path "$FileAuthAdmin"
Copy-Item -Path $FileAuthHome -Destination $FileAuthAdmin -Force
icacls.exe "$FileAuthAdmin" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

## 设置ssh-agent服务
# By default the ssh-agent service is disabled. Allow it to be manually started for the next step to work.
# Make sure you're running as an Administrator.
# Get-Service ssh-agent | Set-Service -StartupType Manual
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
Get-Service ssh-agent
# Now load your key files into ssh-agent
# ssh-add ~\.ssh\id_ed25519

## 安装scoop, 非管理员
# irm get.scoop.sh | iex
# win10 安装scoop的正确姿势 | impressionyang的个人分享站
# https://impressionyang.gitee.io/2021/02/15/win10-install-scoop/

## 安装oh my posh
New-Item -Type File -Force -Path $PROFILE
Clear-Content -Force $PROFILE
# Add-Content -Path $PROFILE -Value 'Set-PSReadlineKeyHandler -Chord Alt+F4 -Function ViExit'
# Add-Content -Path $PROFILE -Value 'Set-PSReadlineKeyHandler -Chord Ctrl+d -Function DeleteCharOrExit'
Add-Content -Path $PROFILE -Value 'Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete'
Add-Content -Path $PROFILE -Value 'Set-PSReadLineOption -EditMode Emacs'
Add-Content -Path $PROFILE -Value '# $env:HTTP_PROXY="http://192.168.44.11:1080"'
Add-Content -Path $PROFILE -Value '# $env:HTTPS_PROXY="http://192.168.44.11:1080"'
if (Get-Command oh-my-posh.exe) {
    Write-Host "oh-my-posh already installed"
} else {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))
    # winget install JanDeDobbeleer.OhMyPosh --source winget
    # scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json
}
if (Get-Command oh-my-posh.exe) {
    Add-Content -Path $PROFILE -Value 'oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/ys.omp.json" | Invoke-Expression'
}

## 设置winget

## windows server 2022安装Windows Terminal
# https://4sysops.com/archives/install-windows-terminal-without-the-store-on-windows-server/

## 启用/禁用代理
# Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" ProxyEnable -value 0
# Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" ProxyEnable -value 1

## 安装powershell 7
# winget install --id Microsoft.Powershell --source winget

## 安装Remote Server Administrator
# Get-WindowsCapability -Online -Name 'Rsat.Server*' | Add-WindowsCapability -Online

## windows auto login
# $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
# $DefaultUsername = "{windowsUser.user}"
# $DefaultPassword = "{windowsUser.password}"
# Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -type String
# Set-ItemProperty $RegPath "DefaultUsername" -Value "$DefaultUsername" -type String
# Set-ItemProperty $RegPath "DefaultPassword" -Value "$DefaultPassword" -type String

## windows auto login
# Microsoft.PowerShell_profile.ps1
# PowerShell Core7でもConsoleのデフォルトエンコーディングはsjisなので必要
# [System.Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("utf-8")
# [System.Console]::InputEncoding = [System.Text.Encoding]::GetEncoding("utf-8")

# git logなどのマルチバイト文字を表示させるため (絵文字含む)
# $env:LESSCHARSET = "utf-8"

## 音を消す
# Set-PSReadlineOption -BellStyle None

## 履歴検索
# scoop install fzf gawk
# Set-PSReadLineKeyHandler -Chord Ctrl+r -ScriptBlock {
#     Set-Alias awk $HOME\scoop\apps\gawk\current\bin\awk.exe
#     $command = Get-Content (Get-PSReadlineOption).HistorySavePath | awk '!a[$0]++' | fzf --tac
#     [Microsoft.PowerShell.PSConsoleReadLine]::Insert($command)
# }