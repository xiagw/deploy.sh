@echo off
:: [保留文件头部注释段不删除]
:: GBK编码，CRLF换行    curl.exe -Lo child.cmd https://gitee.com/xiagw/deploy.sh/raw/main/lib/utils/child.cmd
:: 需求描述：关机前60秒倒计时；每天21:00-08:00时间段和工作日17:00后关机；每次只能开机50分钟，关机后120分钟内不能开机
setlocal EnableDelayedExpansion

:: 设置基础文件名和路径
set "SCRIPT_NAME=%~n0"
set "SCRIPT_PATH=%~dp0"
set "BASE_PATH=%SCRIPT_PATH%%SCRIPT_NAME%"
set "LOGFILE=%BASE_PATH%.log"
set "DEBUG_FILE=%BASE_PATH%_debug.txt"
set "PLAY_FILE=%BASE_PATH%_play.txt"
set "REST_FILE=%BASE_PATH%_rest.txt"
set "PLAY_MINUTES=50"
set "REST_MINUTES=120"
set "WORK_HOUR_8=8"
set "WORK_HOUR_17=17"
set "WORK_HOUR_21=21"
set "DELAY_SECONDS=40"
set "URL_HOST=http://192.168.5.1"
set "URL_PORT=8899"

echo.%1| findstr /i "^debug$ ^d$" >nul && set "DEBUG_MODE=1"
echo.%1| findstr /i "^reset$ ^r$" >nul && goto :RESET
echo.%1| findstr /i "^install$ ^i$" >nul && goto :INSTALL_TASK
echo.%1| findstr /i "^server$ ^s$" >nul && goto :START_SERVER

:: 执行所有时间检查
powershell -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -Command ^
"$error.clear(); ^
try { ^
    $now = Get-Date; ^
    # 设置环境变量
    [Environment]::SetEnvironmentVariable('curr_hour', $now.Hour, 'Process'); ^
    $weekday = [int]$now.DayOfWeek; ^
    if ($weekday -eq 0) { $weekday = 7 }; ^
    [Environment]::SetEnvironmentVariable('weekday', $weekday, 'Process'); ^
    if(-not (Test-Path '%PLAY_FILE%')) { ^
        Set-Content -Path '%PLAY_FILE%' -Value $now.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
    } ^
    if(-not (Test-Path '%REST_FILE%')) { ^
        $startup = Get-Date (Get-Content '%PLAY_FILE%'); ^
        $shutdown = $startup.AddMinutes(-120); ^
        Set-Content -Path '%REST_FILE%' -Value $shutdown.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
    } ^
    $shutdown = Get-Date (Get-Content '%REST_FILE%'); ^
    [Environment]::SetEnvironmentVariable('rest_elapsed', [Math]::Round(($now - $shutdown).TotalMinutes), 'Process'); ^
    $startup = Get-Date (Get-Content '%PLAY_FILE%'); ^
    $play_elapsed = [Math]::Round(($now - $startup).TotalMinutes); ^
    if($startup -le $shutdown) { ^
        Set-Content -Path '%PLAY_FILE%' -Value $now.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
        $play_elapsed = 0; ^
    } ^
    [Environment]::SetEnvironmentVariable('play_elapsed', $play_elapsed, 'Process'); ^
    if ($env:DEBUG_MODE -eq '1') { ^
        Write-Host 'curr_hour=' $env:curr_hour; ^
        Write-Host 'weekday=' $env:weekday; ^
        Write-Host 'rest_elapsed=' $env:rest_elapsed; ^
        Write-Host 'play_elapsed=' $env:play_elapsed; ^
    } ^
} catch { ^
    Write-Host ('错误: ' + $_.Exception.Message) ^
}"

call :TRIGGER

:: 检查关机条件
if %curr_hour% GEQ %WORK_HOUR_21% (
    call :DO_SHUTDOWN "现在是%WORK_HOUR_21%点后，立刻关机"
    exit /b
)
if %curr_hour% LSS %WORK_HOUR_8% (
    call :DO_SHUTDOWN "现在是%WORK_HOUR_8%点前，立刻关机"
    exit /b
)
if %weekday% LEQ 5 (
    if %curr_hour% GEQ %WORK_HOUR_17% (
        call :DO_SHUTDOWN "现在是工作日%WORK_HOUR_17%点后，立刻关机"
        exit /b
    )
)

if %rest_elapsed% LSS %REST_MINUTES% (
    call :DO_SHUTDOWN "距离上次关机未满%REST_MINUTES%分钟，立刻关机"
    exit /b
)

if %play_elapsed% GEQ %PLAY_MINUTES% (
    if "%DEBUG_MODE%"=="1" (
        call :LOG "DEBUG模式: 开机时间超过%PLAY_MINUTES%分钟，立刻关机"
    ) else (
        echo %DATE% %TIME% > "%REST_FILE%"
    )
    call :DO_SHUTDOWN "开机时间超过%PLAY_MINUTES%分钟，立刻关机"
    exit /b
)
:: 结束
goto :END

:: 以下是函数
:RESET
shutdown /a
del /Q /F "%PLAY_FILE%" "%REST_FILE%"
goto :END

:INSTALL_TASK
:: 使用系统账户创建任务
schtasks /Create /NP /TN "%SCRIPT_NAME%" /TR "\"%~f0\"" /SC minute /MO 1 /F /RU SYSTEM >nul 2>&1
if !ERRORLEVEL! equ 0 (
    call :LOG "成功创建计划任务"
) else (
    call :LOG "创建计划任务失败"
    exit /b 1
)
exit /b 0

:DO_SHUTDOWN
if "%DEBUG_MODE%"=="1" (
    call :LOG "DEBUG模式: 触发关机条件: %~1"
    call :LOG "DEBUG模式: 显示启动时间文件内容"
    type "%PLAY_FILE%"
    call :LOG "DEBUG模式: 显示关机时间文件内容"
    type "%REST_FILE%"
    exit /b 0
)
:: 执行关机
call :LOG "执行关机命令: %~1"
shutdown /s /t %DELAY_SECONDS% /c "%~1，系统将在%DELAY_SECONDS%秒后关机" >nul 2>&1
exit /b 0

:: 定义一个记录日志的函数
:LOG
if "%DEBUG_MODE%"=="1" (
    echo [%DATE% %TIME%] %~1
) else (
    echo [%DATE% %TIME%] %~1 >> "%LOGFILE%"
)
exit /b 0

:TRIGGER
curl.exe -fssSL -X POST %URL_HOST%/trigger | findstr /i "rest" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :DO_SHUTDOWN "收到远程关机命令"
    exit /b 0
)
exit /b 1

:TRIGGER2
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"try { ^
    $content = (Invoke-RestMethod -Uri '%URL_HOST%/trigger' -Method POST); ^
    if ($content -match 'rest') { exit 0 } else { exit 1 } ^
} catch { exit 1 }"
if %ERRORLEVEL% EQU 0 (
    call :DO_SHUTDOWN "收到远程关机命令"
    exit /b 0
)
exit /b 1

:START_SERVER
:: 检查管理员权限
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    call :LOG "需要管理员权限运行此命令"
    powershell -Command "Start-Process '%~f0' -Verb RunAs -ArgumentList 'server'"
    exit /b
)

:: 启动简单的HTTP服务器来监听关机命令
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$ErrorActionPreference = 'Stop'; ^
try { ^
    $listener = New-Object System.Net.HttpListener; ^
    $listener.Prefixes.Add('http://+:%URL_PORT%/'); ^
    $listener.Start(); ^
    Write-Host '服务器已启动，监听端口 %URL_PORT%'; ^
    while ($listener.IsListening) { ^
        try { ^
            $context = $listener.GetContext(); ^
            $url = $context.Request.Url.LocalPath; ^
            $response = $context.Response; ^
            try { ^
                if ($url -eq '/rest') { ^
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes('正在执行关机操作'); ^
                    $response.OutputStream.Write($buffer, 0, $buffer.Length); ^
                    $response.Close(); ^
                    shutdown /s /t %DELAY_SECONDS% /c '收到远程关机命令，系统将在%DELAY_SECONDS%秒后关机'; ^
                    break; ^
                } else { ^
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes('服务正在运行'); ^
                    $response.OutputStream.Write($buffer, 0, $buffer.Length); ^
                } ^
            } finally { ^
                if ($response -ne $null) { $response.Close() } ^
            } ^
        } catch { ^
            Write-Host $_.Exception.Message; ^
        } ^
    } ^
} catch { ^
    Write-Host ('错误: ' + $_.Exception.Message); ^
} finally { ^
    if ($listener -ne $null) { ^
        $listener.Stop(); ^
        $listener.Close(); ^
    } ^
}"
exit /b 0

:END
exit /b 0
