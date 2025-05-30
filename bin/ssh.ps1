#Requires -RunAsAdministrator
#Requires -Version 5.1

## 臥心輝念議峇佩貨待
# Get-ExecutionPolicy -List
## 譜崔峇佩貨待葎勣箔垓殻重云禰兆��袈律葎輝念喘薩
# Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

## 壓嶄忽寄遜
# irm https://gitee.com/xiagw/deploy.sh/raw/main/bin/ssh.ps1 | iex
## 音壓壓嶄忽寄遜
# irm https://github.com/xiagw/deploy.sh/raw/main/bin/ssh.ps1 | iex

## 爾試windows
## https://github.com/massgravel/Microsoft-Activation-Scripts
# irm https://massgrave.dev/get | iex

<#
.SYNOPSIS
    Windows狼由塘崔才罷周芦廾重云
.DESCRIPTION
    戻工Windows狼由塘崔、SSH譜崔、罷周芦廾吉孔嬬
.NOTES
    恬宀: xiagw
    井云: 2.0.0
#>
# 重云歌方駅倬壓恷蝕兵
param (
    [string]$ProxyServer = $DEFAULT_PROXY,  # 聞喘潮範旗尖仇峽
    [switch]$UseProxy,
    [string]$Action = "install"  # 潮範強恬
)
#region 畠蕉延楚
# 械楚協吶
$SCRIPT_VERSION = "2.0.0"
$DEFAULT_SHELL = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$DEFAULT_PROXY = "http://192.168.44.11:1080"  # 潮範旗尖仇峽
#endregion

#region 旗尖�犢愃�方
## 畠蕉旗尖譜崔痕方
function Set-GlobalProxy {
    param (
        [string]$ProxyServer = $DEFAULT_PROXY,
        [switch]$Enable,
        [switch]$Disable
    )

    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $envVars = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")

    if ($Enable) {
        # 譜崔旗尖
        if (Test-Path $PROFILE) {
            Add-ProxyToProfile -ProxyServer $ProxyServer
        }
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 1
        Set-ItemProperty -Path $RegPath -Name ProxyServer -Value $ProxyServer

        # 譜崔桟廠延楚
        foreach ($var in $envVars) {
            Set-Item -Path "env:$var" -Value $ProxyServer
        }

        # 譜崔winget旗尖
        Set-WingetConfig -ProxyServer $ProxyServer -Enable
        Write-Output "Global proxy enabled: $ProxyServer"
    }

    if ($Disable) {
        # 卞茅旗尖
        if (Test-Path $PROFILE) {
            Remove-ProxyFromProfile
        }
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 0
        Remove-ItemProperty -Path $RegPath -Name ProxyServer -ErrorAction SilentlyContinue

        # 賠茅桟廠延楚
        foreach ($var in $envVars) {
            Remove-Item -Path "env:$var" -ErrorAction SilentlyContinue
        }

        # 鋤喘winget旗尖
        Set-WingetConfig -Disable
        Write-Output "Global proxy disabled"
    }
}

# 耶紗欺PowerShell塘崔猟周
function Add-ProxyToProfile {
    param (
        [string]$ProxyServer = $DEFAULT_PROXY
    )

    # 殊臥塘崔猟周頁倦贋壓
    if (-not (Test-Path $PROFILE)) {
        New-Item -Type File -Force -Path $PROFILE | Out-Null
    }

    # 響函�嶝佚籌�
    $currentContent = Get-Content $PROFILE -Raw
    if (-not $currentContent) {
        $currentContent = ""
    }

    # 彈姥勣耶紗議旗尖譜崔
    $proxySettings = @"
# 譜崔潮範旗尖
#$env:HTTP_PROXY = '$ProxyServer'
#$env:HTTPS_PROXY = '$ProxyServer'
#$env:ALL_PROXY = '$ProxyServer'
"@

    # 殊臥頁倦厮将贋壓販採旗尖譜崔
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

    # 泌惚短嗤孀欺販採旗尖譜崔��夸耶紗仟議譜崔
    Add-Content -Path $PROFILE -Value "`n$proxySettings"
    Write-Output "Proxy settings added to PowerShell profile"
}

function Remove-ProxyFromProfile {
    # 殊臥塘崔猟周頁倦贋壓
    if (-not (Test-Path $PROFILE)) {
        Write-Output "PowerShell profile does not exist"
        return
    }

    # 響函�嶝佚籌�
    $content = Get-Content $PROFILE -Raw

    if (-not $content) {
        Write-Output "PowerShell profile is empty"
        return
    }

    # 卞茅旗尖�犢愽蕚�
    $newContent = $content -replace "(?ms)# 旗尖酔楯凋綜.*?# 譜崔潮範旗尖.*?\n.*?\n.*?\n.*?\n", ""

    # 泌惚坪否嗤延晒��隠贋猟周
    if ($newContent -ne $content) {
        $newContent.Trim() | Set-Content $PROFILE
        Write-Output "Proxy settings removed from PowerShell profile"
    }
    else {
        Write-Output "No proxy settings found in PowerShell profile"
    }
}
#endregion

#region SSH�犢愃�方
## 芦廾openssh
function Install-OpenSSH {
    param ([switch]$Force)

    Write-Output "Installing and configuring OpenSSH..."

    # 芦廾 OpenSSH 怏周
    Get-WindowsCapability -Online | Where-Object {
        $_.Name -like "OpenSSH*" -and ($_.State -eq "NotPresent" -or $Force)
    } | ForEach-Object {
        Add-WindowsCapability -Online -Name $_.Name
    }

    # 塘崔旺尼強捲暦
    $services = @{
        sshd = @{ StartupType = 'Automatic' }
        'ssh-agent' = @{ StartupType = 'Automatic' }
    }

    foreach ($svc in $services.Keys) {
        Set-Service -Name $svc -StartupType $services[$svc].StartupType
        Start-Service $svc -ErrorAction SilentlyContinue
    }

    # 塘崔契諮能
    if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    }

    # 譜崔 PowerShell 葎潮範 shell
    # New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $DEFAULT_SHELL -Force
    ## 志鹸潮範shell 葎 cmd
    # New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\cmd.exe" -PropertyType String -Force
    # Restart-Service sshd


    # 塘崔 SSH 畜埒
    $sshPaths = @{
        UserKeys = "$HOME\.ssh\authorized_keys"
        AdminKeys = "C:\ProgramData\ssh\administrators_authorized_keys"
        Config = "C:\ProgramData\ssh\sshd_config"
    }

    # 幹秀旺塘崔 SSH 朕村才猟周
    foreach ($path in $sshPaths.Values) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
    }

    # 厚仟 sshd_config
    $configContent = Get-Content $sshPaths.Config -Raw
    @('Match Group administrators', 'AuthorizedKeysFile __PROGRAMDATA__') | ForEach-Object {
        $configContent = $configContent -replace $_, "#$_"
    }
    $configContent | Set-Content $sshPaths.Config

    # 資函旺譜崔 SSH 畜埒
    try {
        $keys = @(
            if (Test-Path $sshPaths.UserKeys) { Get-Content $sshPaths.UserKeys }
            (Invoke-RestMethod 'https://api.github.com/users/xiagw/keys').key
        ) | Select-Object -Unique

        $keys | Set-Content $sshPaths.UserKeys
        Copy-Item $sshPaths.UserKeys $sshPaths.AdminKeys -Force

        # 譜崔砿尖埀畜埒猟周幡��
        icacls.exe $sshPaths.AdminKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

        Write-Output "SSH keys configured (Total: $($keys.Count))"
    }
    catch {
        Write-Warning "Failed to fetch SSH keys: $_"
    }

    # 嶷尼捲暦參哘喘厚個
    Restart-Service sshd
    Write-Output "OpenSSH installation completed!"
}
#endregion

## 芦廾 oh my posh
function Install-OhMyPosh {
    param (
        [switch]$Force,
        [string]$Theme = "ys"
    )

    Write-Output "Setting up Oh My Posh..."

    # 兜兵晒塘崔猟周
    if (-not (Test-Path $PROFILE) -or $Force) {
        New-Item -Type File -Force -Path $PROFILE | Out-Null
        @(
            'Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete',
            'Set-PSReadLineOption -EditMode Emacs'
        ) | Set-Content $PROFILE
    }

    # 芦廾 Oh My Posh
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

    # 塘崔麼籾
    if (Get-Command oh-my-posh.exe -ErrorAction SilentlyContinue) {
        # 響函�嶝佚籌�
        $currentContent = Get-Content $PROFILE -Raw
        if (-not $currentContent) {
            $currentContent = ""
        }

        # 彈姥勣耶紗議 Oh My Posh 塘崔
        $poshConfig = 'oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/' + $Theme + '.omp.json" | Invoke-Expression'

        # 殊臥頁倦厮贋壓 Oh My Posh 塘崔
        $poshPattern = 'oh-my-posh init pwsh --config.*\.omp\.json.*Invoke-Expression'
        if ($currentContent -match $poshPattern) {
            # 泌惚贋壓症塘崔��紋算葎仟塘崔
            $newContent = $currentContent -replace $poshPattern, $poshConfig
            $newContent | Set-Content $PROFILE
            Write-Output "Oh My Posh theme updated to: $Theme"
        } else {
            # 泌惚音贋壓��耶紗仟塘崔
            Add-Content -Path $PROFILE -Value $poshConfig
            Write-Output "Oh My Posh theme configured: $Theme"
        }

        Write-Output "Oh My Posh $(oh-my-posh version) configured with theme: $Theme"
        Write-Output "Please reload profile: . `$PROFILE"
    }
}

# 聞喘幣箭�┸敏墸∧裕遙���
# 児云芦廾
# Install-OhMyPosh

# 膿崙嶷仟芦廾旺聞喘音揖麼籾
# Install-OhMyPosh -Force -Theme "agnoster"

#region 淫砿尖匂�犢愃�方
## 芦廾scoop, 掲砿尖埀
# irm get.scoop.sh | iex
# win10 芦廾scoop議屎鳩徊米 | impressionyang議倖繁蛍�輻�
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
        # 譜崔桟廠
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        $env:HTTPS_PROXY = $ProxyServer

        # 僉夲芦廾坿旺芦廾
        $installUrl = if ($ProxyServer -match "china|cn") {
            "https://gitee.com/glsnames/scoop-installer/raw/master/bin/install.ps1"
        } else {
            "https://get.scoop.sh"
        }

        Invoke-Expression (New-Object Net.WebClient).DownloadString($installUrl)

        # 芦廾児粥怏周
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


# 聞喘幣箭�┸敏墸∧裕遙�:
# 噸宥芦廾
# Install-Scoop

# 膿崙嶷仟芦廾
# Install-Scoop -Force


## 譜崔 winget
function Set-WingetConfig {
    param (
        [string]$ProxyServer,
        [switch]$Enable,
        [switch]$Disable
    )

    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $settingsPath) | Out-Null

    # 紗墮賜幹秀塘崔
    $settings = if (Test-Path $settingsPath) {
        Get-Content $settingsPath -Raw | ConvertFrom-Json
    } else {
        @{ "$schema" = "https://aka.ms/winget-settings.schema.json" }
    }

    # 厚仟塘崔
    if ($Enable -and $ProxyServer) {
        $settings.network = @{ downloader = "wininet"; proxy = $ProxyServer }
        Write-Output "Enabled winget proxy: $ProxyServer"
    } elseif ($Disable -and $settings.network) {
        $settings.PSObject.Properties.Remove('network')
        Write-Output "Disabled winget proxy"
    }

    # 隠贋旺�塋湘籌�
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
    Get-Content $settingsPath

    # 霞編winget
    Write-Output "Testing winget..."
    winget source update
}
# 聞喘幣箭��
# 譜崔winget旗尖
# Set-WingetConfig -ProxyServer "http://192.168.44.11:1080" -Enable

# 鋤喘winget旗尖
# Set-WingetConfig -Disable


#region 嶮極才Shell�犢愃�方
## windows server 2022芦廾Windows Terminal
# method 1 winget install --id Microsoft.WindowsTerminal -e
# method 2 scoop install windows-terminal
# scoop update windows-terminal
function Install-WindowsTerminal {
    param ([switch]$Upgrade)

    # 鳩隠厮芦廾scoop
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Output "Installing Scoop first..."
        Install-Scoop
    }

    # 鳩隠extras bucket厮耶紗
    if (-not (Test-Path "$(scoop prefix scoop)\buckets\extras")) {
        Write-Output "Adding extras bucket..."
        scoop bucket add extras
    }

    try {
        if ($Upgrade) {
            Write-Output "Upgrading Windows Terminal..."
            scoop update windows-terminal
        } else {
            # 殊臥頁倦厮芦廾
            $isInstalled = Get-Command wt -ErrorAction SilentlyContinue
            if ($isInstalled) {
                Write-Output "Windows Terminal is already installed. Use -Upgrade to upgrade."
                return
            }

            Write-Output "Installing Windows Terminal via Scoop..."
            scoop install windows-terminal
        }

        # 塘崔 Terminal
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

    # 殊臥芦廾彜蓑
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh -and -not $Force) {
        Write-Output "PowerShell $(&pwsh -Version) already installed. Use -Force to reinstall."
        return
    }

    try {
        if ($Version -eq "latest") {
            # 聞喘winget芦廾恷仟井云
            winget install --id Microsoft.Powershell --source winget
        } else {
            # 聞喘MSI芦廾蒙協井云
            $msiPath = Join-Path $env:TEMP "PowerShell7\PowerShell-$Version-win-x64.msi"
            New-Item -ItemType Directory -Force -Path (Split-Path $msiPath) | Out-Null

            # 和墮旺芦廾
            Invoke-WebRequest -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$Version/$($msiPath | Split-Path -Leaf)" -OutFile $msiPath
            Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1" -Wait
            Remove-Item -Recurse -Force (Split-Path $msiPath) -ErrorAction SilentlyContinue
        }

        # 刮屬旺塘崔
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

# 聞喘幣箭��
# 芦廾恷仟井云
# Install-PowerShell7

# 膿崙嶷仟芦廾
# Install-PowerShell7 -Force

# 芦廾蒙協井云
# Install-PowerShell7 -Version "7.3.4"

#region 狼由砿尖垢醤�犢愃�方
function Install-RSAT {
    param (
        [switch]$Force,
        [string[]]$Features = @('*'),
        [switch]$ListOnly
    )

    # 資函RSAT孔嬬
    $rsatFeatures = Get-WindowsCapability -Online | Where-Object Name -like "Rsat.Server*"
    if (-not $rsatFeatures) {
        Write-Error "No RSAT features found"
        return
    }

    # 双竃孔嬬賜芦廾
    if ($ListOnly) {
        $rsatFeatures | Format-Table Name, State
        return
    }

    # 標僉旺芦廾孔嬬
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

    # �塋晶畊�
    $installed = @(Get-WindowsCapability -Online | Where-Object {
        $_.Name -like "Rsat.Server*" -and $_.State -eq "Installed"
    }).Count
    Write-Output "RSAT features installed: $installed"
}
#endregion
# 聞喘幣箭��
# 双竃侭嗤辛喘議RSAT孔嬬
# Install-RSAT -ListOnly

# 芦廾侭嗤RSAT孔嬬
# Install-RSAT

# 芦廾蒙協孔嬬�╂�泌DNS才DHCP��
# Install-RSAT -Features 'Dns','Dhcp'

# 膿崙嶷仟芦廾侭嗤孔嬬
# Install-RSAT -Force

# 膿崙嶷仟芦廾蒙協孔嬬
# Install-RSAT -Features 'Dns','Dhcp' -Force

#region 徭強鞠村�犢愃�方
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

# 聞喘幣箭��
# 尼喘徭強鞠村
# Set-WindowsAutoLogin -Username "Administrator" -Password "YourPassword"

# 鋤喘徭強鞠村
# Set-WindowsAutoLogin -Username "Administrator" -Password "YourPassword" -Disable

# 貫紗畜猟周響函鴇象旺塘崔徭強鞠村
function Set-WindowsAutoLoginFromFile {
    param (
        [Parameter(Mandatory=$true)][string]$CredentialFile,
        [switch]$Disable
    )

    try {
        # 刮屬旺響函鴇象
        if (-not (Test-Path $CredentialFile)) { throw "Credential file not found" }
        $cred = Get-Content $CredentialFile | ConvertFrom-Json
        if (-not ($cred.username -and $cred.password)) { throw "Invalid credential format" }

        # 塘崔徭強鞠村
        Set-WindowsAutoLogin -Username $cred.username -Password $cred.password -Disable:$Disable
    }
    catch {
        Write-Error "Failed to configure auto login: $_"
        $false
    }
}

# 聞喘幣箭��
# 幹秀鴇象猟周
# @{username="Administrator"; password="YourPassword"} | ConvertTo-Json | Out-File "C:\credentials.json"

# 貫猟周塘崔徭強鞠村
# Set-WindowsAutoLoginFromFile -CredentialFile "C:\credentials.json"

# 貫猟周鋤喘徭強鞠村
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
            # 鋤喘徭強鞠村
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0" -Type String
            Remove-ItemProperty -Path $RegPath -Name "DefaultUsername" -ErrorAction SilentlyContinue
            cmdkey /delete:$CredTarget
            Unregister-ScheduledTask -TaskName "SecureAutoLogin" -Confirm:$false -ErrorAction SilentlyContinue
            return $true
        }

        if ($Secure) {
            # 資函鴇象旺贋刈
            $SecurePass = Read-Host -Prompt "Enter password for $Username" -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
            $PlainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            cmdkey /generic:$CredTarget /user:$Username /pass:$PlainPass | Out-Null

            # 塘崔廣過燕
            @{
                "AutoAdminLogon" = "1"
                "DefaultUsername" = $Username
                "DefaultDomainName" = $env:COMPUTERNAME
            }.GetEnumerator() | ForEach-Object {
                Set-ItemProperty -Path $RegPath -Name $_.Key -Value $_.Value -Type String
            }

            # 幹秀旺塘崔徭強鞠村重云
            New-Item -ItemType Directory -Force -Path (Split-Path $ScriptPath) | Out-Null
            @"
`$cred = cmdkey /list | Where-Object { `$_ -like "*$CredTarget*" }
if (`$cred) {
    `$username = '$Username'
    `$password = (cmdkey /list | Where-Object { `$_ -like "*$CredTarget*" } | Select-String 'User:').ToString().Split(':')[1].Trim()
}
"@ | Set-Content $ScriptPath

            # 譜崔重云幡�涅夕道�販暦
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
# 聞喘幣箭��
# 塘崔芦畠議徭強鞠村
# Set-SecureAutoLogin -Username "Administrator" -Secure

# 鋤喘徭強鞠村
# Set-SecureAutoLogin -Username "Administrator" -Disable

#region 賠尖痕方
# 賠尖痕方 - 壓重云潤崩扮距喘
function Clear-GlobalSettings {
    $UseProxy -and (Set-GlobalProxy -Disable)
}
#endregion


function Show-ScriptHelp {
    @"
Windows System Configuration Script v$SCRIPT_VERSION

児云喘隈:
    irm https://gitee.com/xiagw/deploy.sh/raw/main/bin/ssh.ps1 -OutFile ssh.ps1

孔嬬:
1. 児粥芦廾: .\ssh.ps1 [-Action install]
2. 聞喘旗尖: .\ssh.ps1 -UseProxy [-ProxyServer "http://proxy:8080"]
3. �塋尚鑾�: .\ssh.ps1 -Action help[|-detailed]
4. 幅雫嶮極: .\ssh.ps1 -Action upgrade

汽鏡孔嬬:
SSH:        -Action ssh[-force]
Terminal:   -Action terminal[-upgrade]
PowerShell: -Action pwsh[-7.3.4]
Oh My Posh: -Action posh[-theme-agnoster]
Scoop:      -Action scoop[-force]
RSAT:       -Action rsat[-dns,dhcp|-list]
AutoLogin:  -Action autologin-[Username|disable]

歌方:
    -Action      : 峇佩荷恬
    -UseProxy    : 尼喘旗尖
    -ProxyServer : 旗尖仇峽 (潮範: $DEFAULT_PROXY)
"@ | Write-Output
}

# 聞喘幣箭��
# Show-ScriptHelp              # �塋昌�云逸廁
# Show-ScriptHelp -Detailed    # �塋章袁鍵鑾�

#region 麼峇佩旗鷹
# 兜兵晒旗尖
$UseProxy -and (Set-GlobalProxy -ProxyServer $ProxyServer -Enable)

# 峇佩荷恬
$actions = @{
    'help(-detailed)?$' = { Show-ScriptHelp -Detailed:($Action -eq "help-detailed") }
    '^install$' = {
        Install-OpenSSH
        Install-OhMyPosh
    }
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

# 峇佩謄塘議荷恬賜�塋尚鑾�
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

# 廣過賠尖荷恬
$PSDefaultParameterValues['*:ProxyServer'] = $ProxyServer
Register-EngineEvent PowerShell.Exiting -Action { Clear-GlobalSettings } | Out-Null
#endregion

# git logなどのマルチバイト猟忖を燕幣させるため (�}猟忖根む)
# $env:LESSCHARSET = "utf-8"

## 咄を��す
# Set-PSReadlineOption -BellStyle None

## 堕�s�碧�
# scoop install fzf gawk
# Set-PSReadLineKeyHandler -Chord Ctrl+r -ScriptBlock {
#     Set-Alias awk $HOME\scoop\apps\gawk\current\bin\awk.exe
#     $command = Get-Content (Get-PSReadlineOption).HistorySavePath | awk '!a[$0]++' | fzf --tac
#     [Microsoft.PowerShell.PSConsoleReadLine]::Insert($command)
# }
