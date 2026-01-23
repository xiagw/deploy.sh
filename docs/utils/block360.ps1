# Block 360 Software Installation and Running
# Author: Claude
# Date: 2024-03-21

# Require administrator privileges
#Requires -RunAsAdministrator

function Uninstall-360Software {
    Write-Host "Starting 360 software uninstallation..." -ForegroundColor Yellow

    # 360 Process names to kill
    $360Processes = @(
        "360safe",
        "360tray",
        "360sd",
        "360rp",
        "360doctor",
        "360chrome",
        "360se",
        "LiveUpdate360",
        "360SafeBox",
        "360Speedup",
        "360WebShield"
    )

    # Kill all 360 related processes
    foreach ($process in $360Processes) {
        Get-Process -Name $process -ErrorAction SilentlyContinue | Stop-Process -Force
    }

    # Common 360 uninstall strings locations
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    # Search and execute uninstallers
    foreach ($path in $uninstallPaths) {
        if (Test-Path $path) {
            Get-ChildItem $path | ForEach-Object {
                $displayName = (Get-ItemProperty $_.PSPath).DisplayName
                if ($displayName -like "*360*") {
                    $uninstallString = (Get-ItemProperty $_.PSPath).UninstallString
                    if ($uninstallString) {
                        Write-Host "Uninstalling: $displayName" -ForegroundColor Yellow
                        try {
                            # Handle different types of uninstall strings
                            if ($uninstallString -like "MsiExec.exe*") {
                                $uninstallArgs = ($uninstallString -split ' ')[1] + " /quiet /norestart"
                                Start-Process "msiexec.exe" -ArgumentList $uninstallArgs -Wait
                            } else {
                                $uninstallString = $uninstallString -replace "`"", ""
                                Start-Process -FilePath $uninstallString -ArgumentList "/S" -Wait
                            }
                        } catch {
                            Write-Host "Failed to uninstall $displayName : $_" -ForegroundColor Red
                        }
                    }
                }
            }
        }
    }

    # Remove 360 directories
    $360BasePaths = @(
        "${env:ProgramFiles}",
        "${env:ProgramFiles(x86)}",
        "${env:SystemDrive}",
        "${env:ProgramData}",
        "${env:LOCALAPPDATA}",
        "${env:APPDATA}"
    )

    $360Keywords = @(
        "360",
        "360safe",
        "360se",
        "360sd",
        "360doctor",
        "360chrome",
        "360Security",
        "360Total"
    )

    foreach ($basePath in $360BasePaths) {
        if (Test-Path $basePath) {
            foreach ($keyword in $360Keywords) {
                try {
                    # 使用 Get-ChildItem 搜索匹配的目录
                    Get-ChildItem -Path $basePath -Directory -Filter "*$keyword*" -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            Remove-Item -Path $_.FullName -Recurse -Force
                            Write-Host "Removed directory: $($_.FullName)" -ForegroundColor Green
                        } catch {
                            Write-Host "Failed to remove directory $($_.FullName) : $_" -ForegroundColor Red
                        }
                    }
                } catch {
                    Write-Host "Failed to search in $basePath : $_" -ForegroundColor Red
                }
            }
        }
    }

    # Clean up registry
    $regPaths = @(
        "HKLM:\SOFTWARE\360Safe",
        "HKLM:\SOFTWARE\360SE",
        "HKCU:\Software\360Safe",
        "HKCU:\Software\360SE",
        "HKLM:\SOFTWARE\WOW6432Node\360Safe",
        "HKLM:\SOFTWARE\WOW6432Node\360SE"
    )

    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            try {
                Remove-Item -Path $regPath -Recurse -Force
                Write-Host "Removed registry key: $regPath" -ForegroundColor Green
            } catch {
                Write-Host "Failed to remove registry key $regPath : $_" -ForegroundColor Red
            }
        }
    }

    Write-Host "360 software uninstallation completed." -ForegroundColor Green
}

function Block-360Software {
    # Block 360 related processes
    $360Processes = @(
        "360safe",
        "360tray",
        "360sd",
        "360rp",
        "360doctor",
        "360chrome",
        "360se"
    )

    # Block 360 installation directories
    $360BasePaths = @(
        "${env:ProgramFiles}",
        "${env:ProgramFiles(x86)}",
        "${env:SystemDrive}"
    )

    # Block 360 download domains
    $360Domains = @(
        "*.360.cn",
        "*.360safe.com",
        "*.360totalsecurity.com",
        "down.360safe.com",
        "update.360safe.com"
    )

    try {
        # Create registry keys to prevent installation
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\360Safe",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\360SE",
            "HKLM:\SOFTWARE\360Safe",
            "HKLM:\SOFTWARE\360SE"
        )

        foreach ($regPath in $regPaths) {
            if (!(Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name "SystemComponent" -Value 1 -Type DWord
            Set-ItemProperty -Path $regPath -Name "NoModify" -Value 1 -Type DWord
            Set-ItemProperty -Path $regPath -Name "NoRepair" -Value 1 -Type DWord
        }

        # Block 360 processes using Windows Defender Firewall
        foreach ($process in $360Processes) {
            $ruleName = "Block360_$process"
            if (!(Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Program "*\$process.exe" -Action Block
                New-NetFirewallRule -DisplayName "$ruleName`_in" -Direction Inbound -Program "*\$process.exe" -Action Block
            }
        }

        # Block 360 domains using hosts file
        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
        $hostsContent = Get-Content $hostsPath
        foreach ($domain in $360Domains) {
            $entry = "127.0.0.1 $domain"
            if ($hostsContent -notcontains $entry) {
                Add-Content -Path $hostsPath -Value $entry
            }
        }

        # Set ACL to prevent access to 360 installation directories
        foreach ($basePath in $360BasePaths) {
            if (Test-Path $basePath) {
                foreach ($keyword in $360Keywords) {
                    # 使用 Get-ChildItem 搜索匹配的目录
                    Get-ChildItem -Path $basePath -Directory -Filter "*$keyword*" -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $acl = Get-Acl $_.FullName
                            $acl.SetAccessRuleProtection($true, $false)
                            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "ContainerInherit,ObjectInherit", "None", "Deny")
                            $acl.AddAccessRule($rule)
                            Set-Acl $_.FullName $acl
                            Write-Host "Blocked access to directory: $($_.FullName)" -ForegroundColor Green
                        } catch {
                            Write-Host "Failed to set ACL on $($_.FullName) : $_" -ForegroundColor Red
                        }
                    }
                }
            }
        }

        Write-Host "Successfully blocked 360 software installation and running." -ForegroundColor Green
    }
    catch {
        Write-Host "Error occurred while blocking 360 software: $_" -ForegroundColor Red
    }
}

# Main execution
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    exit 1
}

# Ask user what action to take
$action = Read-Host "Choose action: [1] Uninstall 360 [2] Block 360 [3] Both (Default: 3)"
if (!$action) { $action = "3" }

switch ($action) {
    "1" {
        Uninstall-360Software
    }
    "2" {
        Block-360Software
    }
    "3" {
        Uninstall-360Software
        Block-360Software
    }
    default {
        Write-Host "Invalid choice. Exiting..." -ForegroundColor Red
        exit 1
    }
}