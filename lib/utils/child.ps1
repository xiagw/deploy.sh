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
    # Write-Output $LogMessage
    Add-Content $LogFile -value $LogMessage
}

function Invoke-Poweroff {
    param ([string]$reason = "正在关机")
    # Write-Output $reason | Show-Notification
    Write-Log $reason
    shutdown.exe /s /t 40 /f /c $reason
}

## 需求描述：关机前40秒倒计时；每天21:00-08:00时间段和工作日17:00后关机；每次只能开机50分钟，每次关机后120分钟内不能开机
$playMinutes = 50
$restMinutes = 120
$AppPath = $PSScriptRoot
$PlayFile = Join-Path $AppPath "child_play.txt"
$RestFile = Join-Path $AppPath "child_rest.txt"
$DisableFile = Join-Path $AppPath "child_disable.txt"
$LogFile = Join-Path $AppPath "child.log"

# Cancel shutdown
if (Test-Path $DisableFile) { return }

$currentTime = Get-Date
$currentHour = (Get-Date -Uformat %H%M)

## 夜间时段判断(21:00-08:00)
if ($currentHour -lt 800 -or $currentHour -gt 2100) {
    Invoke-Poweroff -reason "晚上21点到早上8点期间不能使用电脑"
    return
}

## 工作日17:00后判断
if ((Get-Date).DayOfWeek -in 1..5 -and $currentHour -gt 1700) {
    Invoke-Poweroff -reason "工作日17点后不能使用电脑"
    return
}

## 如果有rest文件，则检查文件内时间是否为120分钟前
if (Test-Path $RestFile) {
    $lastStopTime = Get-Date (Get-Content $RestFile)
    $timeDiff = ($currentTime - $lastStopTime).TotalMinutes

    if ($timeDiff -lt $restMinutes) {
        Invoke-Poweroff -reason "休息时间未到，还需要休息 $([math]::Round($restMinutes - $timeDiff)) 分钟"
        return
    }
}
else {
    # 创建休息文件，内容为120分钟前的时间
    $initialRestTime = $currentTime.AddMinutes(-$restMinutes)
    Set-Content -Path $RestFile -Value $initialRestTime.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline
}

## 如果有play文件，则检查文件内时间是否为50分钟前
if (Test-Path $PlayFile) {
    $playStartTime = Get-Date (Get-Content $PlayFile)
    $playDuration = ($currentTime - $playStartTime).TotalMinutes
    ## 如果play文件内时间为120分钟前，则设置为当前时间
    if ($playDuration -gt $restMinutes) {
        Set-Content -Path $PlayFile -Value $currentTime.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline
        return
    }
    if ($playDuration -gt $playMinutes) {
        Set-Content -Path $RestFile -Value $currentTime.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline
        Invoke-Poweroff -reason "已超过允许使用时间 $playMinutes 分钟"
        return
    }
}
else {
    # 创建play文件，内容为当前时间
    Set-Content -Path $PlayFile -Value $currentTime.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline
}
