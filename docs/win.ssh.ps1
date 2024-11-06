#Requires -RunAsAdministrator
#Requires -Version 5.1

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
        [string]$ProxyServer = "http://192.168.44.11:1080",
        [switch]$Enable,
        [switch]$Disable
    )

    # 系统代理设置注册表路径
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

    # PowerShell会话的代理设置
    if ($Enable) {
        # 设置系统代理
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 1
        Set-ItemProperty -Path $RegPath -Name ProxyServer -Value $ProxyServer

        # 设置环境变量代理
        $env:HTTP_PROXY = $ProxyServer
        $env:HTTPS_PROXY = $ProxyServer
        $env:ALL_PROXY = $ProxyServer

        # 设置 Git 代理
        # git config --global http.proxy $ProxyServer
        # git config --global https.proxy $ProxyServer

        # 设置 npm 代理
        # npm config set proxy $ProxyServer
        # npm config set https-proxy $ProxyServer

        # 设置 pip 代理
        # [System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $ProxyServer, [System.EnvironmentVariableTarget]::User)
        # [System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $ProxyServer, [System.EnvironmentVariableTarget]::User)

        # 添加winget代理设置
        Set-WingetConfig -ProxyServer $ProxyServer -Enable

        Write-Output "Global proxy enabled: $ProxyServer"
    }

    if ($Disable) {
        # 禁用系统代理
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 0
        Remove-ItemProperty -Path $RegPath -Name ProxyServer -ErrorAction SilentlyContinue

        # 清除环境变量代理
        Remove-Item Env:\HTTP_PROXY -ErrorAction SilentlyContinue
        Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue
        Remove-Item Env:\ALL_PROXY -ErrorAction SilentlyContinue

        # 清除 Git 代理
        # git config --global --unset http.proxy
        # git config --global --unset https.proxy

        # 清除 npm 代理
        # npm config delete proxy
        # npm config delete https-proxy

        # 清除 pip 代理
        # [System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $null, [System.EnvironmentVariableTarget]::User)
        # [System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $null, [System.EnvironmentVariableTarget]::User)

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

    # 准备要添加的代理设置
    $proxySettings = @"
# 代理快捷命令
function Enable-Proxy { Set-GlobalProxy -ProxyServer '$ProxyServer' -Enable }
function Disable-Proxy { Set-GlobalProxy -Disable }
# 设置默认代理
`$env:HTTP_PROXY = '$ProxyServer'
`$env:HTTPS_PROXY = '$ProxyServer'
`$env:ALL_PROXY = '$ProxyServer'
"@

    # 检查是否已经存在代理设置
    if ($currentContent -and ($currentContent -match "Enable-Proxy|HTTP_PROXY = '$ProxyServer'")) {
        Write-Output "Proxy settings already exist in PowerShell profile"
        return
    }

    # 添加代理设置
    Add-Content -Path $PROFILE -Value "`n$proxySettings"
    Write-Output "Proxy settings added to PowerShell profile"
}
#endregion

#region SSH相关函数
## 安装openssh
function Install-OpenSSH {
    param (
        [switch]$Force
    )

    Write-Output "Checking OpenSSH installation..."

    # 检查OpenSSH组件
    $sshComponents = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH*" }

    # 如果没有找到任何OpenSSH组件，则可能是系统不支持
    if (-not $sshComponents) {
        Write-Error "OpenSSH components not found in this system"
        return
    }

    # 安装缺失的OpenSSH组件
    $sshComponents | Where-Object {
        $_.State -eq "NotPresent" -or $Force
    } | ForEach-Object {
        Write-Output "Installing $($_.Name)..."
        Add-WindowsCapability -Online -Name $_.Name
    }

    # 启动并设置SSHD服务
    try {
        # 启动SSHD服务
        Start-Service sshd -ErrorAction Stop
        # 设置自动启动
        Set-Service -Name sshd -StartupType 'Automatic'
        Write-Output "SSHD service started and set to automatic start"
    }
    catch {
        Write-Error "Failed to start SSHD service: $_"
        return
    }

    # 配置防火墙规则
    if (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue) {
        Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' already exists"
    }
    else {
        Write-Output "Creating firewall rule for OpenSSH..."
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
            -DisplayName 'OpenSSH Server (sshd)' `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22
    }

    # 设置默认shell为PowerShell
    Write-Output "Setting PowerShell as default SSH shell..."
    $powerShellPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" `
        -Name DefaultShell `
        -Value $powerShellPath `
        -PropertyType String `
        -Force

    # 配置sshd_config
    Write-Output "Configuring sshd_config..."
    $sshdConfigPath = "C:\ProgramData\ssh\sshd_config"
    if (Test-Path $sshdConfigPath) {
        # 注释掉管理员组的特殊配置
        (Get-Content -Path $sshdConfigPath -Raw) -replace 'Match Group administrators','#Match Group administrators' |
            Set-Content -Path $sshdConfigPath
        (Get-Content -Path $sshdConfigPath -Raw) -replace 'AuthorizedKeysFile __PROGRAMDATA__','#AuthorizedKeysFile __PROGRAMDATA__' |
            Set-Content -Path $sshdConfigPath
    }

    # 重启SSHD服务以应用更改
    Write-Output "Restarting SSHD service..."
    Restart-Service sshd

    # 设置authorized_keys
    Write-Output "Setting up authorized_keys..."

    # 为普通用户设置
    $FileAuthHome = "$HOME\.ssh\authorized_keys"
    if (-not (Test-Path $FileAuthHome)) {
        New-Item -Path $FileAuthHome -Type File -Force
        Write-Output "Created $FileAuthHome"
    }

    # 获取并添加SSH密钥
    try {
        (Invoke-RestMethod 'https://api.github.com/users/xiagw/keys').key |
            Add-Content -Path $FileAuthHome
        Write-Output "Added SSH keys to $FileAuthHome"
    }
    catch {
        Write-Warning "Failed to fetch SSH keys: $_"
    }

    # 为管理员设置
    $FileAuthAdmin = "C:\ProgramData\ssh\administrators_authorized_keys"
    if (-not (Test-Path $FileAuthAdmin)) {
        New-Item -Path $FileAuthAdmin -Type File -Force
        Write-Output "Created $FileAuthAdmin"
    }

    # 复制密钥到管理员文件
    Copy-Item -Path $FileAuthHome -Destination $FileAuthAdmin -Force

    # 设置正确的权限
    icacls.exe $FileAuthAdmin /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
    Write-Output "Set permissions for $FileAuthAdmin"

    # 设置并启动ssh-agent服务
    Write-Output "Configuring ssh-agent service..."
    Get-Service ssh-agent | Set-Service -StartupType Automatic
    Start-Service ssh-agent

    Write-Output "OpenSSH installation and configuration completed!"
}
#endregion


## 安装 oh my posh
function Install-OhMyPosh {
    param (
        [switch]$Force,
        [string]$Theme = "ys"
    )

    Write-Output "Setting up Oh My Posh..."

    # 创建或清理PowerShell配置文件
    if (-not (Test-Path $PROFILE) -or $Force) {
        Write-Output "Creating/Resetting PowerShell profile..."
        New-Item -Type File -Force -Path $PROFILE | Out-Null
        Clear-Content -Force $PROFILE
    }

    # 添加基本PowerShell配置
    Write-Output "Configuring PowerShell settings..."
    $basicSettings = @(
        'Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete',
        'Set-PSReadLineOption -EditMode Emacs'
        # 可选的其他设置
        # 'Set-PSReadlineKeyHandler -Chord Alt+F4 -Function ViExit',
        # 'Set-PSReadlineKeyHandler -Chord Ctrl+d -Function DeleteCharOrExit'
    )
    $basicSettings | ForEach-Object {
        Add-Content -Path $PROFILE -Value $_
    }

    # 检查是否已安装Oh My Posh
    $needInstall = $Force -or -not (Get-Command oh-my-posh.exe -ErrorAction SilentlyContinue)

    if ($needInstall) {
        Write-Output "Installing Oh My Posh..."
        try {
            # 设置执行策略
            Set-ExecutionPolicy Bypass -Scope Process -Force

            # 选择安装方法
            $installMethod = if ($ProxyServer -match "china|cn|alibaba|aliyun") {
                Write-Output "Using alternative installation method..."
                # 这里可以添加国内镜像源的安装方法
                "scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json"
            } else {
                Write-Output "Using official installation method..."
                "winget install JanDeDobbeleer.OhMyPosh --source winget"
            }

            # 执行安装
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))
        }
        catch {
            Write-Error "Failed to install Oh My Posh: $_"
            return
        }
        finally {
            # 清除代理设置
            if ($ProxyServer) {
                Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-Output "Oh My Posh is already installed"
    }

    # 验证安装并配置主题
    if (Get-Command oh-my-posh.exe -ErrorAction SilentlyContinue) {
        Write-Output "Configuring Oh My Posh theme..."


        # 添加Oh My Posh初始化到配置文件
        $poshInit = 'oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/' + $Theme + '.omp.json" | Invoke-Expression'
        Add-Content -Path $PROFILE -Value $poshInit

        # 显示版本信息
        $version = oh-my-posh version
        Write-Output "Oh My Posh $version installed and configured successfully!"

        # 提示重新加载配置
        Write-Output "Please reload your PowerShell profile by running: . `$PROFILE"
    }
    else {
        Write-Error "Oh My Posh installation could not be verified"
    }
}
#endregion

# 使用示例（可以注释掉）：
# 基本安装
# Install-OhMyPosh

# 强制重新安装并使用不同主题
# Install-OhMyPosh -Force -Theme "agnoster"


#region 终端和Shell相关函数
## windows server 2022安装Windows Terminal
function Install-WindowsTerminal {
    param (
        [switch]$Upgrade
    )

    # 检查是否已安装Windows Terminal
    $isInstalled = Get-Command wt -ErrorAction SilentlyContinue
    if ($isInstalled -and -not $Upgrade) {
        Write-Output "Windows Terminal is already installed. Use -Upgrade to force upgrade."
        return
    }

    # 获取已安装版本(如果存在)
    $currentVersion = $null
    if ($isInstalled) {
        try {
            $currentVersion = (Get-AppxPackage Microsoft.WindowsTerminal).Version
            Write-Output "Current Windows Terminal version: $currentVersion"
        }
        catch {
            Write-Warning "Failed to get current version: $_"
        }
    }

    Write-Output "$(if ($Upgrade) {'Upgrading'} else {'Installing'}) Windows Terminal..."

    # 创建临时目录
    $tempDir = Join-Path $env:TEMP "WindowsTerminal"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    try {
        # 获取最新版本信息
        $releaseUrl = "https://api.github.com/repos/microsoft/terminal/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl
        $latestVersion = $release.tag_name -replace '[^0-9.]'
        $msixBundleUrl = ($release.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url

        Write-Output "Latest version available: $latestVersion"

        # 检查是否需要升级
        if ($currentVersion -and ($currentVersion -eq $latestVersion)) {
            Write-Output "Already running latest version ($latestVersion)"
            return
        }

        if (-not $msixBundleUrl) {
            throw "Could not find Windows Terminal download URL"
        }

        # 下载Windows Terminal
        $msixBundlePath = Join-Path $tempDir "WindowsTerminal.msixbundle"
        Write-Output "Downloading Windows Terminal $latestVersion..."
        Invoke-WebRequest -Uri $msixBundleUrl -OutFile $msixBundlePath

        # 获取依赖包版本信息
        Write-Output "Checking dependencies versions..."

        # 获取VCLibs最新版本
        $vcLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $vcLibsVersion = (Invoke-WebRequest -Uri $vcLibsUrl -Method Head).Headers.'Content-Disposition' -replace '.*filename=.*_(\d+\.\d+\.\d+\.\d+)\.appx.*','$1'
        Write-Output "Latest VCLibs version: $vcLibsVersion"

        # 获取UI Xaml最新版本
        $uiXamlVersions = @("2.8", "2.7", "2.6")
        $uiXamlUrl = $null
        $uiXamlVersion = $null

        foreach ($version in $uiXamlVersions) {
            $testUrl = "https://aka.ms/Microsoft.UI.Xaml.$version.x64.appx"
            try {
                $response = Invoke-WebRequest -Uri $testUrl -Method Head -ErrorAction Stop
                $uiXamlUrl = $testUrl
                $uiXamlVersion = $version
                Write-Output "Found UI Xaml version: $version"
                break
            }
            catch {
                Write-Output "UI Xaml version $version not available, trying next..."
                continue
            }
        }

        if (-not $uiXamlUrl) {
            throw "Could not find a compatible UI Xaml version"
        }

        # 下载依赖包
        $depsInfo = @(
            @{
                Name = "VCLibs"
                Url = $vcLibsUrl
                Version = $vcLibsVersion
            },
            @{
                Name = "UI Xaml"
                Url = $uiXamlUrl
                Version = $uiXamlVersion
            }
        )

        foreach ($dep in $depsInfo) {
            $fileName = Split-Path $dep.Url -Leaf
            $filePath = Join-Path $tempDir $fileName
            Write-Output "Downloading $($dep.Name) version $($dep.Version)..."

            try {
                Invoke-WebRequest -Uri $dep.Url -OutFile $filePath
                Write-Output "Successfully downloaded $($dep.Name)"
            }
            catch {
                Write-Error "Failed to download $($dep.Name): $_"
                throw
            }
        }

        # 安装依赖包
        Write-Output "Installing dependencies..."
        Get-ChildItem $tempDir -Filter "*.appx" | ForEach-Object {
            try {
                Write-Output "Installing $($_.Name)..."
                Add-AppxPackage -Path $_.FullName -ErrorAction Stop
                Write-Output "Successfully installed $($_.Name)"
            }
            catch {
                Write-Error "Failed to install $($_.Name): $_"
                throw
            }
        }

        # 安装/升级Windows Terminal
        Write-Output "$(if ($Upgrade) {'Upgrading'} else {'Installing'}) Windows Terminal..."
        Add-AppxPackage -Path $msixBundlePath -ForceApplicationShutdown

        Write-Output "Windows Terminal $(if ($Upgrade) {'upgraded'} else {'installed'}) successfully to version $latestVersion!"

        # 如果是升级,保留原有配置
        if ($Upgrade) {
            $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
            if (Test-Path "$settingsPath.backup") {
                Write-Output "Restoring previous settings..."
                Copy-Item "$settingsPath.backup" $settingsPath -Force
            }
        }
    }
    catch {
        Write-Error "Failed to $(if ($Upgrade) {'upgrade'} else {'install'}) Windows Terminal: $_"
    }
    finally {
        # 清理临时文件
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
}


#region 包管理器相关函数
function Install-Scoop {
    param (
        [switch]$Force
    )

    Write-Output "Checking Scoop installation..."

    # 检查是否已安装
    if ((Get-Command scoop -ErrorAction SilentlyContinue) -and -not $Force) {
        Write-Output "Scoop is already installed. Use -Force to reinstall."
        return
    }

    try {
        # 设置TLS
        $securityProtocol = [Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # 检查执行策略
        $executionPolicy = Get-ExecutionPolicy
        if ($executionPolicy -ne 'RemoteSigned' -and $executionPolicy -ne 'Unrestricted') {
            Write-Output "Setting execution policy to RemoteSigned..."
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        }

        # 设置代理
        if ($ProxyServer) {
            $env:HTTPS_PROXY = $ProxyServer
            Write-Output "Using proxy: $ProxyServer"
        }

        # 选择安装源
        $installScript = if ($ProxyServer -match "china|cn|alibaba|aliyun") {
            # 使用 Gitee 镜像
            Write-Output "Using Gitee mirror for installation..."
            "https://gitee.com/glsnames/scoop-installer/raw/master/bin/install.ps1"
        } else {
            # 使用官方源
            Write-Output "Using official source for installation..."
            "https://get.scoop.sh"
        }

        # 安装Scoop
        Write-Output "Installing Scoop..."
        Invoke-Expression (New-Object System.Net.WebClient).DownloadString($installScript)

        # 添加常用bucket
        Write-Output "Adding common buckets..."
        scoop bucket add extras
        scoop bucket add versions

        # 安装一些基本工具
        Write-Output "Installing basic tools..."
        scoop install git 7zip

        Write-Output "Scoop installation completed successfully!"

        # 显示版本信息
        Write-Output "Scoop version:"
        scoop --version
    }
    catch {
        Write-Error "Failed to install Scoop: $_"
    }
    finally {
        # 恢复原来的安全协议设置
        [Net.ServicePointManager]::SecurityProtocol = $securityProtocol
        # 清除代理设置
        if ($ProxyServer) {
            Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue
        }
    }
}
#endregion
## 安装scoop, 非管理员
# irm get.scoop.sh | iex
# win10 安装scoop的正确姿势 | impressionyang的个人分享站
# https://impressionyang.gitee.io/2021/02/15/win10-install-scoop/

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

    Write-Output "Configuring winget settings..."

    # winget 设置文件路径
    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"

    # 确保设置目录存在
    $settingsDir = Split-Path $settingsPath -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    # 创建或加载现有配置
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    }
    else {
        $settings = @{
            "$schema" = "https://aka.ms/winget-settings.schema.json"
        }
    }

    if ($Enable -and $ProxyServer) {
        # 配置网络设置
        $settings.network = @{
            downloader = "wininet"
            proxy = $ProxyServer
        }
        Write-Output "Enabled winget proxy: $ProxyServer"
    }
    elseif ($Disable) {
        # 移除代理设置
        if ($settings.network) {
            $settings.network.PSObject.Properties.Remove('proxy')
            if (-not $settings.network.PSObject.Properties.Name) {
                $settings.PSObject.Properties.Remove('network')
            }
        }
        Write-Output "Disabled winget proxy"
    }

    # 保存设置
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath

    # 显示当前配置
    Write-Output "Current winget settings:"
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


function Install-PowerShell7 {
    param (
        [switch]$Force,
        [string]$Version = "latest"
    )

    Write-Output "Checking PowerShell 7 installation..."

    # 检查是否已安装
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh -and -not $Force) {
        $currentVersion = & pwsh -Version
        Write-Output "PowerShell $currentVersion is already installed. Use -Force to reinstall."
        return
    }

    try {
        Write-Output "Installing PowerShell 7..."

        if ($Version -eq "latest") {
            # 使用winget安装最新版本
            Write-Output "Installing latest version via winget..."
            winget install --id Microsoft.Powershell --source winget
        }
        else {
            # 使用MSI安装特定版本
            $tempDir = Join-Path $env:TEMP "PowerShell7"
            New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

            # 构建下载URL
            $architecture = "x64"
            $msiName = "PowerShell-$Version-win-$architecture.msi"
            $downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/$msiName"

            # 下载MSI
            $msiPath = Join-Path $tempDir $msiName
            Write-Output "Downloading PowerShell $Version..."
            Invoke-WebRequest -Uri $downloadUrl -OutFile $msiPath

            # 安装MSI
            Write-Output "Installing PowerShell $Version..."
            Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1" -Wait

            # 清理临时文件
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        }

        # 验证安装
        $newPwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($newPwsh) {
            $installedVersion = & pwsh -Version
            Write-Output "PowerShell $installedVersion installed successfully!"

            # 添加到PATH（如果需要）
            $pwshPath = Split-Path $newPwsh.Source -Parent
            if ($env:Path -notlike "*$pwshPath*") {
                [Environment]::SetEnvironmentVariable(
                    "Path",
                    [Environment]::GetEnvironmentVariable("Path", "User") + ";$pwshPath",
                    "User"
                )
                Write-Output "Added PowerShell 7 to PATH"
            }

            # 可选：设置为默认shell
            if ($Force) {
                Write-Output "Setting PowerShell 7 as default shell..."
                $pwshPath = $newPwsh.Source
                New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $pwshPath -PropertyType String -Force
            }
        }
        else {
            throw "PowerShell 7 installation could not be verified"
        }
    }
    catch {
        Write-Error "Failed to install PowerShell 7: $_"
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
        [string[]]$Features = @('*'),  # 默认安装所有功能
        [switch]$ListOnly             # 仅列出可用功能
    )

    Write-Output "Checking Remote Server Administration Tools (RSAT)..."

    # 获取所有RSAT功能
    $rsatFeatures = Get-WindowsCapability -Online | Where-Object {
        $_.Name -like "Rsat.Server*"
    }

    # 如果没有找到RSAT功能
    if (-not $rsatFeatures) {
        Write-Error "No RSAT features found on this system"
        return
    }

    # 如果只是列出可用功能
    if ($ListOnly) {
        Write-Output "Available RSAT features:"
        $rsatFeatures | Format-Table Name, State
        return
    }

    # 过滤要安装的功能
    $featuresToInstall = $rsatFeatures | Where-Object {
        $feature = $_
        $shouldInstall = $false

        # 检查是否需要安装此功能
        foreach ($pattern in $Features) {
            if ($feature.Name -like "Rsat.Server.$pattern") {
                $shouldInstall = $true
                break
            }
        }

        # 如果功能未安装或强制安装
        $shouldInstall -and ($Force -or $feature.State -eq "NotPresent")
    }

    if (-not $featuresToInstall) {
        Write-Output "No matching RSAT features found to install"
        return
    }

    # 安装选定的功能
    $total = $featuresToInstall.Count
    $current = 0

    foreach ($feature in $featuresToInstall) {
        $current++
        Write-Progress -Activity "Installing RSAT Features" `
            -Status "Installing $($feature.Name)" `
            -PercentComplete (($current / $total) * 100)

        try {
            Write-Output "Installing $($feature.Name)..."
            Add-WindowsCapability -Online -Name $feature.Name
        }
        catch {
            Write-Error "Failed to install $($feature.Name): $_"
        }
    }

    Write-Progress -Activity "Installing RSAT Features" -Completed

    # 验证安装
    $installedFeatures = Get-WindowsCapability -Online | Where-Object {
        $_.Name -like "Rsat.Server*" -and $_.State -eq "Installed"
    }

    Write-Output "`nInstallation Summary:"
    Write-Output "Total RSAT features installed: $($installedFeatures.Count)"
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
        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [switch]$Disable
    )

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

    try {
        if ($Disable) {
            Write-Output "Disabling Windows Auto Login..."

            # 禁用自动登录
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0" -Type String

            # 移除自动登录相关的注册表项
            Remove-ItemProperty -Path $RegPath -Name "DefaultUsername" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $RegPath -Name "DefaultPassword" -ErrorAction SilentlyContinue

            Write-Output "Windows Auto Login has been disabled"
        }
        else {
            Write-Output "Configuring Windows Auto Login..."
            Write-Output "Username: $Username"

            # 启用自动登录
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "1" -Type String
            Set-ItemProperty -Path $RegPath -Name "DefaultUsername" -Value $Username -Type String
            Set-ItemProperty -Path $RegPath -Name "DefaultPassword" -Value $Password -Type String

            # 可选：设置自动登录尝试次数（0表示无限次）
            Set-ItemProperty -Path $RegPath -Name "AutoLogonCount" -Value "0" -Type DWord

            Write-Output "Windows Auto Login has been configured successfully"
            Write-Warning "The system will automatically login as $Username after restart"
        }
    }
    catch {
        Write-Error "Failed to configure Windows Auto Login: $_"
        return $false
    }

    return $true
}

# 使用示例：
# 启用自动登录
# Set-WindowsAutoLogin -Username "Administrator" -Password "YourPassword"

# 禁用自动登录
# Set-WindowsAutoLogin -Username "Administrator" -Password "YourPassword" -Disable

# 从加密文件读取凭据并配置自动登录
function Set-WindowsAutoLoginFromFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$CredentialFile,
        [switch]$Disable
    )

    try {
        # 检查凭据文件是否存在
        if (-not (Test-Path $CredentialFile)) {
            throw "Credential file not found: $CredentialFile"
        }

        # 读取并解密凭据
        $credentials = Get-Content $CredentialFile | ConvertFrom-Json

        # 验证凭据格式
        if (-not $credentials.username -or -not $credentials.password) {
            throw "Invalid credential file format. Expected {username, password}"
        }

        # 配置自动登录
        if ($Disable) {
            Set-WindowsAutoLogin -Username $credentials.username -Password $credentials.password -Disable
        }
        else {
            Set-WindowsAutoLogin -Username $credentials.username -Password $credentials.password
        }
    }
    catch {
        Write-Error "Failed to configure auto login from file: $_"
        return $false
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
        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(ParameterSetName="SetLogin")]
        [switch]$Secure,

        [Parameter(ParameterSetName="DisableLogin")]
        [switch]$Disable
    )

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $CredentialTarget = "WindowsAutoLogin"

    try {
        if ($Disable) {
            Write-Output "Disabling Windows Auto Login..."

            # 禁用自动登录
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0" -Type String
            Remove-ItemProperty -Path $RegPath -Name "DefaultUsername" -ErrorAction SilentlyContinue

            # 删除存储的凭据
            cmdkey /delete:$CredentialTarget

            Write-Output "Windows Auto Login has been disabled"
            return $true
        }

        if ($Secure) {
            Write-Output "Configuring Secure Windows Auto Login..."
            Write-Output "Username: $Username"

            # 提示用户安全输入密码
            $SecurePassword = Read-Host -Prompt "Enter password for $Username" -AsSecureString
            $Credential = New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)

            # 使用Windows凭据管理器存储凭据
            $BinaryPassword = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
            $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BinaryPassword)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BinaryPassword)

            # 存储凭据到Windows凭据管理器
            cmdkey /generic:$CredentialTarget /user:$Username /pass:$PlainPassword | Out-Null

            # 配置注册表以使用凭据管理器
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "1" -Type String
            Set-ItemProperty -Path $RegPath -Name "DefaultUsername" -Value $Username -Type String
            Set-ItemProperty -Path $RegPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Type String

            # 创建自动登录脚本
            $ScriptPath = "$env:ProgramData\AutoLogin"
            $ScriptFile = "$ScriptPath\AutoLogin.ps1"

            if (-not (Test-Path $ScriptPath)) {
                New-Item -ItemType Directory -Path $ScriptPath | Out-Null
            }

            # 创建自动登录脚本
            @"
# 自动登录脚本
`$cred = cmdkey /list | Where-Object { `$_ -like "*$CredentialTarget*" }
if (`$cred) {
    `$username = '$Username'
    `$password = (cmdkey /list | Where-Object { `$_ -like "*$CredentialTarget*" } | Select-String 'User:').ToString().Split(':')[1].Trim()
    # 使用凭据执行登录
    # 这里可以添加其他登录后需要执行的操作
}
"@ | Set-Content $ScriptFile

            # 设置脚本权限
            $Acl = Get-Acl $ScriptFile
            $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
            $Acl.SetAccessRule($Ar)
            Set-Acl $ScriptFile $Acl

            # 创建计划任务在启动时运行脚本
            $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptFile`""
            $Trigger = New-ScheduledTaskTrigger -AtStartup
            $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

            Register-ScheduledTask -TaskName "SecureAutoLogin" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force

            Write-Output "Secure Windows Auto Login has been configured successfully"
            Write-Warning "The system will automatically login as $Username after restart"
            Write-Warning "Credentials are stored securely in Windows Credential Manager"
        }
    }
    catch {
        Write-Error "Failed to configure Secure Windows Auto Login: $_"
        return $false
    }

    return $true
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
    if ($UseProxy) {
        Write-Output "Cleaning up proxy settings..."
        Set-GlobalProxy -Disable
    }
}
#endregion

#region 主执行代码
# 初始化代理设置
if ($UseProxy) {
    Write-Output "Initializing global proxy settings..."
    Set-GlobalProxy -ProxyServer $ProxyServer -Enable
}

# 根据Action参数执行相应操作
switch ($Action) {
    "help" { Show-ScriptHelp }
    "help-detailed" { Show-ScriptHelp -Detailed }
    "upgrade" { Install-WindowsTerminal -Upgrade }
    "install" {
        Install-OpenSSH
        Install-WindowsTerminal
    }
}

# 在原有的配置文件设置中添加代理配置
if (Test-Path $PROFILE) {
    Write-Output "Adding proxy settings to PowerShell profile..."
    Add-ProxyToProfile
}

# 配置Windows Terminal
$settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $settingsPath) {
    Write-Output "Configuring Windows Terminal..."

    # 备份原始设置
    Copy-Item $settingsPath "$settingsPath.backup"

    # 读取现有设置
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

    # 配置默认设置
    $settings.defaultProfile = "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}" # PowerShell的GUID
    $settings.profiles.defaults = @{
        "fontFace" = "Cascadia Code"
        "fontSize" = 12
        "colorScheme" = "One Half Dark"
        "useAcrylic" = $true
        "acrylicOpacity" = 0.8
    }

    # 保存设置
    $settings | ConvertTo-Json -Depth 32 | Set-Content $settingsPath

    Write-Output "Windows Terminal configured successfully!"
}

# 注册脚本结束时的清理操作
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

function Show-ScriptHelp {
    param (
        [switch]$Detailed
    )

    $helpText = @"
Windows System Configuration Script v$SCRIPT_VERSION

基本用法:
    irm https://gitee.com/xiagw/deploy.sh/raw/main/docs/win.ssh.ps1 | iex [-Args @{UseProxy=`$true}]

参数:
    -UseProxy          启用代理
    -ProxyServer      设置代理服务器地址 (默认: $DEFAULT_PROXY)

主要功能:
    1. SSH服务
       Install-OpenSSH [-Force]                    # 安装并配置OpenSSH服务

    2. 终端工具
       Install-WindowsTerminal [-Upgrade]          # 安装/升级Windows Terminal
       Install-PowerShell7 [-Force] [-Version]     # 安装PowerShell 7
       Install-OhMyPosh [-Force] [-Theme <name>]   # 安装Oh My Posh

    3. 包管理器
       Install-Scoop [-Force]                      # 安装Scoop包管理器

    4. 系统工具
       Install-RSAT [-ListOnly] [-Features <名称>] # 安装远程服务器管理工具
       Set-SecureAutoLogin -Username <用户名> -Secure  # 配置安全的自动登录

    5. 代理设置
       Set-GlobalProxy -Enable/-Disable            # 启用/禁用全局代理
       Set-WingetConfig -Enable/-Disable           # 配置winget代理

示例:
    # 使用代理安装
    irm https://gitee.com/xiagw/deploy.sh/raw/main/docs/win.ssh.ps1 | iex -Args @{UseProxy=`$true}

    # 安装特定版本的PowerShell
    Install-PowerShell7 -Version "7.3.4"

    # 列出可用的RSAT功能
    Install-RSAT -ListOnly
"@

    if ($Detailed) {
        $helpText += @"

详细说明:
1. OpenSSH安装
   - 安装SSH服务器和客户端组件
   - 配置防火墙规则
   - 设置默认shell
   - 配置SSH密钥

2. Windows Terminal
   - 安装必要的依赖
   - 配置默认设置
   - 支持自动升级

3. PowerShell 7
   - 支持多种安装方式
   - 自动添加到PATH
   - 可选设置为默认shell

4. 代理设置
   - 支持系统级代理
   - 支持多种工具的代理配置
   - 自动清理功能

注意事项:
1. 需要管理员权限运行
2. 某些功能可能需要重启
3. 建议在安装前备份重要数据
"@
    }

    Write-Output $helpText
}

# 使用示例：
# Show-ScriptHelp              # 显示基本帮助
# Show-ScriptHelp -Detailed    # 显示详细帮助