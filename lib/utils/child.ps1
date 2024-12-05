param (
    [switch]$Debug
)

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
    Add-Content $LogFile -value "$(Get-Date): $LogString"
    if ($Debug) {
        Write-Host "$(Get-Date): $LogString"
    }
}

function Invoke-Poweroff {
    param ([string]$reason = "正在关机")
    # Write-Output $reason | Show-Notification
    Write-Log $reason
    if ($Debug) {
        Write-Host "Debug模式: 模拟关机操作，原因: $reason" -ForegroundColor Yellow
    } else {
        shutdown.exe /s /t 40 /f /c $reason
    }
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
$currentHour = $currentTime.ToString('HHmm')

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
    if ($Debug) {
        Write-Host "休息时间检查: 上次停止时间 $lastStopTime, 已休息 $timeDiff 分钟" -ForegroundColor Cyan
    }
    if ($timeDiff -lt $restMinutes) {
        Invoke-Poweroff -reason "还需要休息 $([math]::Round($restMinutes - $timeDiff)) 分钟"
        return
    }
}
else {
    # 创建休息文件，内容为120分钟前的时间
    $initialRestTime = $currentTime.AddMinutes(-$restMinutes)
    Write-TimeFile -FilePath $RestFile -TimeValue $initialRestTime
}

## 如果有play文件，则检查文件内时间是否为50分钟前
if (Test-Path $PlayFile) {
    $playStartTime = Get-Date (Get-Content $PlayFile)
    $playDuration = ($currentTime - $playStartTime).TotalMinutes
    if ($Debug) {
        Write-Host "使用时间检查: 开始时间 $playStartTime, 已使用 $playDuration 分钟" -ForegroundColor Cyan
    }
    ## 如果play文件内时间为120分钟前，则设置为当前时间
    if ($playDuration -gt $restMinutes) {
        Write-TimeFile -FilePath $PlayFile -TimeValue $currentTime
        return
    }
    if ($playDuration -gt $playMinutes) {
        Write-TimeFile -FilePath $RestFile -TimeValue $currentTime
        Invoke-Poweroff -reason "已超过允许使用时间 $playMinutes 分钟"
        return
    }
}
else {
    # 创建play文件，内容为当前时间
    Write-TimeFile -FilePath $PlayFile -TimeValue $currentTime
}
