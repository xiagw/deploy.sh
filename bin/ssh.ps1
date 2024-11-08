#Requires -RunAsAdministrator
#Requires -Version 5.1

## 查看当前的执行策略
# Get-ExecutionPolicy -List
## 设置执行策略为要求远程脚本签名，范围为当前用户
# Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

## 在中国大陆
# irm https://gitee.com/xiagw/deploy.sh/raw/main/bin/ssh.ps1 | iex
## 不在在中国大陆
# irm https://github.com/xiagw/deploy.sh/raw/main/bin/ssh.ps1 | iex

## 激活windows
## https://github.com/massgravel/Microsoft-Activation-Scripts
# irm https://massgrave.dev/get | iex

<#
.SYNOPSIS
    Windows系统配置和软件安装脚本
.DESCRIPTION
    提供Windows系统配置、SSH设置、软件安装等功能
.NOTES
    作者: xiagw
    版本: 1.0
#>
# 脚本参数必须在最开始
param (
    [string]$ProxyServer = $DEFAULT_PROXY,  # 使用默认代理地址
    [switch]$UseProxy,
    [string]$Action = "install"  # 默认动作
)
#region 全局变量
# 常量定义
$SCRIPT_VERSION = "2.0.0"
$DEFAULT_SHELL = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$DEFAULT_PROXY = "http://192.168.44.11:1080"  # 默认代理地址
#endregion

#region 代理相关函数
## 全局代理设置函数
function Set-GlobalProxy {
    param (
        [string]$ProxyServer = $DEFAULT_PROXY,
        [switch]$Enable,
        [switch]$Disable
    )

    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $envVars = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")

    if ($Enable) {
        # 设置代理
        if (Test-Path $PROFILE) {
            Add-ProxyToProfile -ProxyServer $ProxyServer
        }
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 1
        Set-ItemProperty -Path $RegPath -Name ProxyServer -Value $ProxyServer

        # 设置环境变量
        foreach ($var in $envVars) {
            Set-Item -Path "env:$var" -Value $ProxyServer
        }

        # 设置winget代理
        Set-WingetConfig -ProxyServer $ProxyServer -Enable
        Write-Output "Global proxy enabled: $ProxyServer"
    }

    if ($Disable) {
        # 移除代理
        if (Test-Path $PROFILE) {
            Remove-ProxyFromProfile
        }
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 0
        Remove-ItemProperty -Path $RegPath -Name ProxyServer -ErrorAction SilentlyContinue

        # 清除环境变量
        foreach ($var in $envVars) {
            Remove-Item -Path "env:$var" -ErrorAction SilentlyContinue
        }

        # 禁用winget代理
        Set-WingetConfig -Disable
        Write-Output "Global proxy disabled"
    }
}

# 添加到PowerShell配置文件
function Add-ProxyToProfile {
    param (
        [string]$ProxyServer = $DEFAULT_PROXY
    )

    # 检查配置文件是否存在
    if (-not (Test-Path $PROFILE)) {
        New-Item -Type File -Force -Path $PROFILE | Out-Null
    }

    # 读取现有配置
    $currentContent = Get-Content $PROFILE -Raw
    if (-not $currentContent) {
        $currentContent = ""
    }

    # 准备要添加的代理设置
    $proxySettings = @"
# 代理快捷命令
# function Enable-Proxy { Set-GlobalProxy -ProxyServer '$ProxyServer' -Enable }
# function Disable-Proxy { Set-GlobalProxy -Disable }
# 设置默认代理
`$env:HTTP_PROXY = '$ProxyServer'
`$env:HTTPS_PROXY = '$ProxyServer'
`$env:ALL_PROXY = '$ProxyServer'
"@

    # 检查是否已经存在任何代理设置
    $proxyPatterns = @(
        [regex]::Escape($proxySettings),
        "HTTP_PROXY = ['`"]$([regex]::Escape($ProxyServer))['`"]",
        "HTTPS_PROXY = ['`"]$([regex]::Escape($ProxyServer))['`"]",
        "ALL_PROXY = ['`"]$([regex]::Escape($ProxyServer))['`"]"
    )

    foreach ($pattern in $proxyPatterns) {
        if ($currentContent -match $pattern) {
            Write-Output "Proxy settings already exist in PowerShell profile"
            return
        }
    }

    # 如果没有找到任何代理设置，则添加新的设置
    Add-Content -Path $PROFILE -Value "`n$proxySettings"
    Write-Output "Proxy settings added to PowerShell profile"
}

function Remove-ProxyFromProfile {
    # 检查配置文件是否存在
    if (-not (Test-Path $PROFILE)) {
        Write-Output "PowerShell profile does not exist"
        return
    }

    # 读取现有配置
    $content = Get-Content $PROFILE -Raw

    if (-not $content) {
        Write-Output "PowerShell profile is empty"
        return
    }

    # 移除代理相关设置
    $newContent = $content -replace "(?ms)# 代理快捷命令.*?# 设置默认代理.*?\n.*?\n.*?\n.*?\n", ""

    # 如果内容有变化，保存文件
    if ($newContent -ne $content) {
        $newContent.Trim() | Set-Content $PROFILE
        Write-Output "Proxy settings removed from PowerShell profile"
    }
    else {
        Write-Output "No proxy settings found in PowerShell profile"
    }
}
#endregion

#region SSH相关函数
## 安装openssh
function Install-OpenSSH {
    param ([switch]$Force)

    Write-Output "Installing and configuring OpenSSH..."

    # 安装 OpenSSH 组件
    Get-WindowsCapability -Online | Where-Object {
        $_.Name -like "OpenSSH*" -and ($_.State -eq "NotPresent" -or $Force)
    } | ForEach-Object {
        Add-WindowsCapability -Online -Name $_.Name
    }

    # 配置并启动服务
    $services = @{
        sshd = @{ StartupType = 'Automatic' }
        'ssh-agent' = @{ StartupType = 'Automatic' }
    }

    foreach ($svc in $services.Keys) {
        Set-Service -Name $svc -StartupType $services[$svc].StartupType
        Start-Service $svc -ErrorAction SilentlyContinue
    }

    # 配置防火墙
    if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    }

    # 设置 PowerShell 为默认 shell
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Force

    # 配置 SSH 密钥
    $sshPaths = @{
        UserKeys = "$HOME\.ssh\authorized_keys"
        AdminKeys = "C:\ProgramData\ssh\administrators_authorized_keys"
        Config = "C:\ProgramData\ssh\sshd_config"
    }

    # 创建并配置 SSH 目录和文件
    foreach ($path in $sshPaths.Values) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
    }

    # 更新 sshd_config
    $configContent = Get-Content $sshPaths.Config -Raw
    @('Match Group administrators', 'AuthorizedKeysFile __PROGRAMDATA__') | ForEach-Object {
        $configContent = $configContent -replace $_, "#$_"
    }
    $configContent | Set-Content $sshPaths.Config

    # 获取并设置 SSH 密钥
    try {
        $keys = @(
            if (Test-Path $sshPaths.UserKeys) { Get-Content $sshPaths.UserKeys }
            (Invoke-RestMethod 'https://api.github.com/users/xiagw/keys').key
        ) | Select-Object -Unique

        $keys | Set-Content $sshPaths.UserKeys
        Copy-Item $sshPaths.UserKeys $sshPaths.AdminKeys -Force

        # 设置管理员密钥文件权限
        icacls.exe $sshPaths.AdminKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

        Write-Output "SSH keys configured (Total: $($keys.Count))"
    }
    catch {
        Write-Warning "Failed to fetch SSH keys: $_"
    }

    # 重启服务以应用更改
    Restart-Service sshd
    Write-Output "OpenSSH installation completed!"
}
#endregion

## 安装 oh my posh
function Install-OhMyPosh {
    param (
        [switch]$Force,
        [string]$Theme = "ys"
    )

    Write-Output "Setting up Oh My Posh..."

    # 初始化配置文件
    if (-not (Test-Path $PROFILE) -or $Force) {
        New-Item -Type File -Force -Path $PROFILE | Out-Null
        @(
            'Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete',
            'Set-PSReadLineOption -EditMode Emacs'
        ) | Set-Content $PROFILE
    }

    # 安装 Oh My Posh
    if ($Force -or -not (Get-Command oh-my-posh.exe -ErrorAction SilentlyContinue)) {
        try {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            $installCmd = if ($ProxyServer -match "china|cn") {
                "scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json"
            } else {
                "winget install JanDeDobbeleer.OhMyPosh --source winget"
            }
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))
        }
        catch {
            Write-Error "Failed to install Oh My Posh: $_"
            return
        }
    }

    # 配置主题
    if (Get-Command oh-my-posh.exe -ErrorAction SilentlyContinue) {
        # 读取现有配置
        $currentContent = Get-Content $PROFILE -Raw
        if (-not $currentContent) {
            $currentContent = ""
        }

        # 准备要添加的 Oh My Posh 配置
        $poshConfig = 'oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/' + $Theme + '.omp.json" | Invoke-Expression'

        # 检查是否已存在 Oh My Posh 配置
        $poshPattern = 'oh-my-posh init pwsh --config.*\.omp\.json.*Invoke-Expression'
        if ($currentContent -match $poshPattern) {
            # 如果存在旧配置，替换为新配置
            $newContent = $currentContent -replace $poshPattern, $poshConfig
            $newContent | Set-Content $PROFILE
            Write-Output "Oh My Posh theme updated to: $Theme"
        } else {
            # 如果不存在，添加新配置
            Add-Content -Path $PROFILE -Value $poshConfig
            Write-Output "Oh My Posh theme configured: $Theme"
        }

        Write-Output "Oh My Posh $(oh-my-posh version) configured with theme: $Theme"
        Write-Output "Please reload profile: . `$PROFILE"
    }
}

# 使用示例（可以注释掉）：
# 基本安装
# Install-OhMyPosh

# 强制重新安装并使用不同主题
# Install-OhMyPosh -Force -Theme "agnoster"

#region 包管理器相关函数
## 安装scoop, 非管理员
# irm get.scoop.sh | iex
# win10 安装scoop的正确姿势 | impressionyang的个人分享站
# https://impressionyang.gitee.io/2021/02/15/win10-install-scoop/

# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
function Install-Scoop {
    param ([switch]$Force)

    if ((Get-Command scoop -ErrorAction SilentlyContinue) -and -not $Force) {
        Write-Output "Scoop already installed. Use -Force to reinstall."
        return
    }

    try {
        # 设置环境
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        $env:HTTPS_PROXY = $ProxyServer

        # 选择安装源并安装
        $installUrl = if ($ProxyServer -match "china|cn") {
            "https://gitee.com/glsnames/scoop-installer/raw/master/bin/install.ps1"
        } else {
            "https://get.scoop.sh"
        }

        Invoke-Expression (New-Object Net.WebClient).DownloadString($installUrl)

        # 安装基础组件
        @("extras", "versions") | ForEach-Object { scoop bucket add $_ }
        scoop install git 7zip

        Write-Output "Scoop $(scoop --version) installed successfully!"
    }
    catch {
        Write-Error "Scoop installation failed: $_"
    }
    finally {
        Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue
    }
}
#endregion


# 使用示例（可以注释掉）:
# 普通安装
# Install-Scoop

# 强制重新安装
# Install-Scoop -Force


## 设置 winget
function Set-WingetConfig {
    param (
        [string]$ProxyServer,
        [switch]$Enable,
        [switch]$Disable
    )

    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $settingsPath) | Out-Null

    # 加载或创建配置
    $settings = if (Test-Path $settingsPath) {
        Get-Content $settingsPath -Raw | ConvertFrom-Json
    } else {
        @{ "$schema" = "https://aka.ms/winget-settings.schema.json" }
    }

    # 更新配置
    if ($Enable -and $ProxyServer) {
        $settings.network = @{ downloader = "wininet"; proxy = $ProxyServer }
        Write-Output "Enabled winget proxy: $ProxyServer"
    } elseif ($Disable -and $settings.network) {
        $settings.PSObject.Properties.Remove('network')
        Write-Output "Disabled winget proxy"
    }

    # 保存并显示配置
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
    Get-Content $settingsPath

    # 测试winget
    Write-Output "Testing winget..."
    winget source update
}
# 使用示例：
# 设置winget代理
# Set-WingetConfig -ProxyServer "http://192.168.44.11:1080" -Enable

# 禁用winget代理
# Set-WingetConfig -Disable


#region 终端和Shell相关函数
## windows server 2022安装Windows Terminal
# method 1 winget install --id Microsoft.WindowsTerminal -e
# method 2 scoop install windows-terminal
# scoop update windows-terminal
function Install-WindowsTerminal {
    param ([switch]$Upgrade)

    # 确保已安装scoop
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Output "Installing Scoop first..."
        Install-Scoop
    }

    # 确保extras bucket已添加
    if (-not (Test-Path "$(scoop prefix scoop)\buckets\extras")) {
        Write-Output "Adding extras bucket..."
        scoop bucket add extras
    }

    try {
        if ($Upgrade) {
            Write-Output "Upgrading Windows Terminal..."
            scoop update windows-terminal
        } else {
            # 检查是否已安装
            $isInstalled = Get-Command wt -ErrorAction SilentlyContinue
            if ($isInstalled) {
                Write-Output "Windows Terminal is already installed. Use -Upgrade to upgrade."
                return
            }

            Write-Output "Installing Windows Terminal via Scoop..."
            scoop install windows-terminal
        }

        # 配置 Terminal
        $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        if (Test-Path $settingsPath) {
            Copy-Item $settingsPath "$settingsPath.backup"
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            $settings.defaultProfile = "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}"
            $settings.profiles.defaults = @{
                fontFace = "Cascadia Code"
                fontSize = 12
                colorScheme = "One Half Dark"
                useAcrylic = $true
                acrylicOpacity = 0.9
            }
            $settings | ConvertTo-Json -Depth 32 | Set-Content $settingsPath
        }

        Write-Output "Windows Terminal $(scoop info windows-terminal | Select-String 'Version:' | ForEach-Object { $_.ToString().Split(':')[1].Trim() }) installed successfully!"
    }
    catch {
        Write-Error "Installation failed: $_"
    }
}

function Install-PowerShell7 {
    param (
        [switch]$Force,
        [string]$Version = "latest"
    )

    # 检查安装状态
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh -and -not $Force) {
        Write-Output "PowerShell $(&pwsh -Version) already installed. Use -Force to reinstall."
        return
    }

    try {
        if ($Version -eq "latest") {
            # 使用winget安装最新版本
            winget install --id Microsoft.Powershell --source winget
        } else {
            # 使用MSI安装特定版本
            $msiPath = Join-Path $env:TEMP "PowerShell7\PowerShell-$Version-win-x64.msi"
            New-Item -ItemType Directory -Force -Path (Split-Path $msiPath) | Out-Null

            # 下载并安装
            Invoke-WebRequest -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$Version/$($msiPath | Split-Path -Leaf)" -OutFile $msiPath
            Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1" -Wait
            Remove-Item -Recurse -Force (Split-Path $msiPath) -ErrorAction SilentlyContinue
        }

        # 验证并配置
        if ($newPwsh = Get-Command pwsh -ErrorAction SilentlyContinue) {
            $pwshPath = Split-Path $newPwsh.Source -Parent
            if ($env:Path -notlike "*$pwshPath*") {
                [Environment]::SetEnvironmentVariable("Path", "$([Environment]::GetEnvironmentVariable('Path', 'User'));$pwshPath", "User")
            }
            $Force -and (New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $newPwsh.Source -Force)
            Write-Output "PowerShell $(&pwsh -Version) installed successfully!"
        }
    }
    catch {
        Write-Error "Installation failed: $_"
    }
}

# 使用示例：
# 安装最新版本
# Install-PowerShell7

# 强制重新安装
# Install-PowerShell7 -Force

# 安装特定版本
# Install-PowerShell7 -Version "7.3.4"

#region 系统管理工具相关函数
function Install-RSAT {
    param (
        [switch]$Force,
        [string[]]$Features = @('*'),
        [switch]$ListOnly
    )

    # 获取RSAT功能
    $rsatFeatures = Get-WindowsCapability -Online | Where-Object Name -like "Rsat.Server*"
    if (-not $rsatFeatures) {
        Write-Error "No RSAT features found"
        return
    }

    # 列出功能或安装
    if ($ListOnly) {
        $rsatFeatures | Format-Table Name, State
        return
    }

    # 筛选并安装功能
    $toInstall = $rsatFeatures | Where-Object {
        ($_.State -eq "NotPresent" -or $Force) -and
        ($Features -eq '*' -or $Features | Where-Object { $_.Name -like "Rsat.Server.$_" })
    }

    if ($toInstall) {
        $total = $toInstall.Count
        $toInstall | ForEach-Object -Begin {
            $i = 0
        } {
            $i++
            Write-Progress -Activity "Installing RSAT" -Status $_.Name -PercentComplete ($i/$total*100)
            try {
                Add-WindowsCapability -Online -Name $_.Name
            } catch {
                Write-Error "Failed to install $($_.Name): $_"
            }
        }
        Write-Progress -Activity "Installing RSAT" -Completed
    }

    # 显示结果
    $installed = @(Get-WindowsCapability -Online | Where-Object {
        $_.Name -like "Rsat.Server*" -and $_.State -eq "Installed"
    }).Count
    Write-Output "RSAT features installed: $installed"
}
#endregion
# 使用示例：
# 列出所有可用的RSAT功能
# Install-RSAT -ListOnly

# 安装所有RSAT功能
# Install-RSAT

# 安装特定功能（例如DNS和DHCP）
# Install-RSAT -Features 'Dns','Dhcp'

# 强制重新安装所有功能
# Install-RSAT -Force

# 强制重新安装特定功能
# Install-RSAT -Features 'Dns','Dhcp' -Force

#region 自动登录相关函数
function Set-WindowsAutoLogin {
    param (
        [Parameter(Mandatory=$true)][string]$Username,
        [Parameter(Mandatory=$true)][string]$Password,
        [switch]$Disable
    )

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $RegSettings = @{
        AutoAdminLogon = if ($Disable) { "0" } else { "1" }
        DefaultUsername = $Username
        DefaultPassword = $Password
        AutoLogonCount = "0"
    }

    try {
        if ($Disable) {
            Write-Output "Disabling Windows Auto Login..."
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0" -Type String
            "DefaultUsername", "DefaultPassword" | ForEach-Object {
                Remove-ItemProperty -Path $RegPath -Name $_ -ErrorAction SilentlyContinue
            }
        } else {
            Write-Output "Configuring Windows Auto Login for $Username..."
            $RegSettings.Keys | ForEach-Object {
                Set-ItemProperty -Path $RegPath -Name $_ -Value $RegSettings[$_] -Type $(if ($_ -eq "AutoLogonCount") {"DWord"} else {"String"})
            }
            Write-Warning "System will auto login as $Username after restart"
        }
        $true
    }
    catch {
        Write-Error "Auto Login configuration failed: $_"
        $false
    }
}

# 使用示例：
# 启用自动登录
# Set-WindowsAutoLogin -Username "Administrator" -Password "YourPassword"

# 禁用自动登录
# Set-WindowsAutoLogin -Username "Administrator" -Password "YourPassword" -Disable

# 从加密文件读取凭据并配置自动登录
function Set-WindowsAutoLoginFromFile {
    param (
        [Parameter(Mandatory=$true)][string]$CredentialFile,
        [switch]$Disable
    )

    try {
        # 验证并读取凭据
        if (-not (Test-Path $CredentialFile)) { throw "Credential file not found" }
        $cred = Get-Content $CredentialFile | ConvertFrom-Json
        if (-not ($cred.username -and $cred.password)) { throw "Invalid credential format" }

        # 配置自动登录
        Set-WindowsAutoLogin -Username $cred.username -Password $cred.password -Disable:$Disable
    }
    catch {
        Write-Error "Failed to configure auto login: $_"
        $false
    }
}

# 使用示例：
# 创建凭据文件
# @{username="Administrator"; password="YourPassword"} | ConvertTo-Json | Out-File "C:\credentials.json"

# 从文件配置自动登录
# Set-WindowsAutoLoginFromFile -CredentialFile "C:\credentials.json"

# 从文件禁用自动登录
# Set-WindowsAutoLoginFromFile -CredentialFile "C:\credentials.json" -Disable

function Set-SecureAutoLogin {
    param (
        [Parameter(Mandatory=$true)][string]$Username,
        [Parameter(ParameterSetName="SetLogin")][switch]$Secure,
        [Parameter(ParameterSetName="DisableLogin")][switch]$Disable
    )

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $CredTarget = "WindowsAutoLogin"
    $ScriptPath = "$env:ProgramData\AutoLogin\AutoLogin.ps1"

    try {
        if ($Disable) {
            # 禁用自动登录
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0" -Type String
            Remove-ItemProperty -Path $RegPath -Name "DefaultUsername" -ErrorAction SilentlyContinue
            cmdkey /delete:$CredTarget
            Unregister-ScheduledTask -TaskName "SecureAutoLogin" -Confirm:$false -ErrorAction SilentlyContinue
            return $true
        }

        if ($Secure) {
            # 获取凭据并存储
            $SecurePass = Read-Host -Prompt "Enter password for $Username" -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
            $PlainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            cmdkey /generic:$CredTarget /user:$Username /pass:$PlainPass | Out-Null

            # 配置注册表
            @{
                "AutoAdminLogon" = "1"
                "DefaultUsername" = $Username
                "DefaultDomainName" = $env:COMPUTERNAME
            }.GetEnumerator() | ForEach-Object {
                Set-ItemProperty -Path $RegPath -Name $_.Key -Value $_.Value -Type String
            }

            # 创建并配置自动登录脚本
            New-Item -ItemType Directory -Force -Path (Split-Path $ScriptPath) | Out-Null
            @"
`$cred = cmdkey /list | Where-Object { `$_ -like "*$CredTarget*" }
if (`$cred) {
    `$username = '$Username'
    `$password = (cmdkey /list | Where-Object { `$_ -like "*$CredTarget*" } | Select-String 'User:').ToString().Split(':')[1].Trim()
}
"@ | Set-Content $ScriptPath

            # 设置脚本权限和计划任务
            $Acl = Get-Acl $ScriptPath
            $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
            $Acl.SetAccessRule($Ar)
            Set-Acl $ScriptPath $Acl

            $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
            Register-ScheduledTask -TaskName "SecureAutoLogin" -Action $Action `
                -Trigger (New-ScheduledTaskTrigger -AtStartup) `
                -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest) `
                -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) -Force

            Write-Warning "System will auto login as $Username after restart"
            return $true
        }
    }
    catch {
        Write-Error "Secure Auto Login configuration failed: $_"
        return $false
    }
}
#endregion
# 使用示例：
# 配置安全的自动登录
# Set-SecureAutoLogin -Username "Administrator" -Secure

# 禁用自动登录
# Set-SecureAutoLogin -Username "Administrator" -Disable

#region 清理函数
# 清理函数 - 在脚本结束时调用
function Clear-GlobalSettings {
    $UseProxy -and (Set-GlobalProxy -Disable)
}
#endregion


function Show-ScriptHelp {
    @"
Windows System Configuration Script v$SCRIPT_VERSION

基本用法:
    irm https://gitee.com/xiagw/deploy.sh/raw/main/bin/ssh.ps1 -OutFile ssh.ps1

功能:
1. 基础安装: .\ssh.ps1 [-Action install]
2. 使用代理: .\ssh.ps1 -UseProxy [-ProxyServer "http://proxy:8080"]
3. 显示帮助: .\ssh.ps1 -Action help[|-detailed]
4. 升级终端: .\ssh.ps1 -Action upgrade

单独功能:
SSH:        -Action ssh[-force]
Terminal:   -Action terminal[-upgrade]
PowerShell: -Action pwsh[-7.3.4]
Oh My Posh: -Action posh[-theme-agnoster]
Scoop:      -Action scoop[-force]
RSAT:       -Action rsat[-dns,dhcp|-list]
AutoLogin:  -Action autologin-[Username|disable]

参数:
    -Action      : 执行操作
    -UseProxy    : 启用代理
    -ProxyServer : 代理地址 (默认: $DEFAULT_PROXY)
"@ | Write-Output
}

# 使用示例：
# Show-ScriptHelp              # 显示基本帮助
# Show-ScriptHelp -Detailed    # 显示详细帮助

#region 主执行代码
# 初始化代理
$UseProxy -and (Set-GlobalProxy -ProxyServer $ProxyServer -Enable)

# 执行操作
$actions = @{
    'help(-detailed)?$' = { Show-ScriptHelp -Detailed:($Action -eq "help-detailed") }
    '^install$' = { Install-OpenSSH }
    '^ssh(-force)?$' = { Install-OpenSSH -Force:($Action -eq "ssh-force") }
    '^upgrade$' = { Install-WindowsTerminal -Upgrade }
    '^terminal(-upgrade)?$' = { Install-WindowsTerminal -Upgrade:($Action -eq "terminal-upgrade") }
    '^pwsh(-[\d\.]+)?$' = {
        Install-PowerShell7 -Version $(if ($Action -eq "pwsh") {"latest"} else {$Action -replace "^pwsh-",""})
    }
    '^posh(-theme-.*)?$' = {
        Install-OhMyPosh -Theme $(if ($Action -eq "posh") {"ys"} else {$Action -replace "^posh-theme-",""})
    }
    '^scoop(-force)?$' = { Install-Scoop -Force:($Action -eq "scoop-force") }
    '^rsat(-list|-.*)?$' = {
        switch -Regex ($Action) {
            '^rsat-list$' { Install-RSAT -ListOnly }
            '^rsat-(.+)$' { Install-RSAT -Features ($Action -replace "^rsat-","").Split(',') }
            default { Install-RSAT }
        }
    }
    '^autologin-(.+)$' = {
        $username = $Action -replace "^autologin-",""
        Set-SecureAutoLogin -Username $(if ($username -eq "disable") {"Administrator"} else {$username}) `
            -$(if ($username -eq "disable") {"Disable"} else {"Secure"})
    }
}

# 执行匹配的操作或显示帮助
$executed = $false
foreach ($pattern in $actions.Keys) {
    if ($Action -match $pattern) {
        & $actions[$pattern]
        $executed = $true
        break
    }
}

if (-not $executed) {
    Write-Output "Unknown action: $Action"
    Show-ScriptHelp
}

# 注册清理操作
$PSDefaultParameterValues['*:ProxyServer'] = $ProxyServer
Register-EngineEvent PowerShell.Exiting -Action { Clear-GlobalSettings } | Out-Null
#endregion

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
