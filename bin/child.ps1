
function Show-Notification {
    [cmdletbinding()]
    Param (
        [string]
        $ToastTitle,
        [string]
        [parameter(ValueFromPipeline)]
        $ToastText
    )

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
    $Template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)

    $RawXml = [xml] $Template.GetXml()
    ($RawXml.toast.visual.binding.text | Where-object { $_.id -eq "1" }).AppendChild($RawXml.CreateTextNode($ToastTitle)) > $null
    ($RawXml.toast.visual.binding.text | Where-object { $_.id -eq "2" }).AppendChild($RawXml.CreateTextNode($ToastText)) > $null

    $SerializedXml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $SerializedXml.LoadXml($RawXml.OuterXml)

    $Toast = [Windows.UI.Notifications.ToastNotification]::new($SerializedXml)
    $Toast.Tag = "PowerShell"
    $Toast.Group = "PowerShell"
    $Toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(1)

    $Notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("PowerShell")
    $Notifier.Show($Toast);
}

function Write-Log {
    Param ([string]$LogString)
    $LogTime = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $LogMessage = "$LogTime $LogString"
    Add-Content $LogFile -value $LogMessage
}

function Invoke-Poweroff {
    Write-Output "正在关机 - 休息2小时" | Show-Notification
    # Start-Sleep -Seconds 30
    Write-Log "Shutdown."
    shutdown.exe /s /t 30 /f
    # Stop-Computer -Force
}

# $AppPath = Get-Location
$AppPath = $PSScriptRoot
$PlayFile = Join-Path $AppPath "child.play"
$RestFile = Join-Path $AppPath "child.rest"
$CancelFile = Join-Path $AppPath "child.cancel"
$LogFile = Join-Path $AppPath "child.log"
$PlayMinutes = 40
$RestMinutes = 120

# Cancel shutdown
if (Test-Path $CancelFile) {
    return
}

## study mode, program with vscode, but no minecraft

## homework mode, week 1-4, after 19:30, always shutdown
if ( ((Get-Date -Uformat %w) -lt 5) -and ((Get-Date -Uformat %H%M) -gt 1910) ) {
    Invoke-Poweroff
    return
}

# Check if it's time to rest
if (Test-Path $RestFile) {
    $RestTime = (Get-Item $RestFile).LastWriteTime
    if ((Get-Date).AddMinutes(-$RestMinutes) -gt $RestTime) {
        Remove-Item $RestFile, $PlayFile -Force -ErrorAction SilentlyContinue
    }
    else {
        Invoke-Poweroff
        return
    }
}

# (Get-Date) - (gcim Win32_OperatingSystem).LastBootUpTime
#### play #####################################
if (Test-Path $PlayFile) {
    $timePlayFile = (Get-Item $PlayFile).LastWriteTime
    if ((Get-Date).AddMinutes(-$restMinutes) -gt $timePlayFile) {
        New-Item -Path $PlayFile -Type File -Force
        return
    }
    if ((Get-Date).AddMinutes(-$playMinutes) -gt $timePlayFile) {
        New-Item -Path $RestFile -Type File -Force
        Invoke-Poweroff
    }
}
else {
    New-Item -Path $PlayFile -Type File -Force
}
