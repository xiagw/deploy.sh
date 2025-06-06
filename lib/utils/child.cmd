@echo off
:: [保留文件头部注释段不删除]
:: GBK编码，CRLF换行  curl.exe -Lo child.cmd https://gitee.com/xiagw/deploy.sh/raw/main/lib/utils/child.cmd
:: 需求描述：关机前40秒倒计时；每天21:00-08:00时间段和工作日17:00后关机；每次只能开机50分钟，每次关机后90分钟内不能开机
setlocal EnableDelayedExpansion

:: 设置基础文件名和路径
set "SCRIPT_NAME=%~n0"
set "SCRIPT_PATH=%~dp0"
set "BASE_PATH=%SCRIPT_PATH%%SCRIPT_NAME%"
set "LOGFILE=%BASE_PATH%.log"
set "DEBUG_FILE=%BASE_PATH%_debug.txt"
set "PLAY_FILE=%BASE_PATH%_play.txt"
set "REST_FILE=%BASE_PATH%_rest.txt"
set "DISABLE_FILE=%BASE_PATH%_disable.txt"
set "PLAY_MINUTES=50"
set "REST_MINUTES=90"
set "DELAY_SECONDS=40"
set "URL_HOST=http://192.168.5.1"
set "URL_PORT=8899"

echo.%1| findstr /i "^debug$ ^d$" >nul && set "DEBUG_MODE=1"
echo.%1| findstr /i "^reset$ ^r$" >nul && goto :RESET
echo.%1| findstr /i "^upgrade$ ^u$" >nul && goto :UPGRADE
echo.%1| findstr /i "^install$ ^i$" >nul && goto :INSTALL_TASK
echo.%1| findstr /i "^server$ ^s$" >nul && goto :START_SERVER
echo.%1| findstr /i "^disable$ ^x$" >nul && goto :DISABLE

if exist "%DISABLE_FILE%" ( exit /b 0 )

:: 执行所有时间检查
:: powershell -NoLogo -NonInteractive -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%~f0"
powershell -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -Command ^
"$error.clear(); ^
try { ^
    $result = @{}; ^
    $now = Get-Date; ^
    $result.curr_hour = $now.Hour; ^
    $result.weekday = [int]$now.DayOfWeek; ^
    if ($result.weekday -eq 0) { $result.weekday = 7 }; ^
    if(-not (Test-Path '%PLAY_FILE%')) { ^
        Set-Content -Path '%PLAY_FILE%' -Value $now.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
    } ^
    if(-not (Test-Path '%REST_FILE%')) { ^
        $shutdown = $now.AddMinutes(-%REST_MINUTES%); ^
        Set-Content -Path '%REST_FILE%' -Value $shutdown.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
    } ^
    $shutdown = Get-Date (Get-Content '%REST_FILE%'); ^
    $result.rest_elapsed = [Math]::Round(($now - $shutdown).TotalMinutes); ^
    $startup = Get-Date (Get-Content '%PLAY_FILE%'); ^
    $result.play_elapsed = [Math]::Round(($now - $startup).TotalMinutes); ^
    if($result.play_elapsed -gt %REST_MINUTES%) { ^
        Set-Content -Path '%PLAY_FILE%' -Value $now.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
        $result.play_elapsed = 0; ^
    } ^
    foreach($k in $result.Keys) { Write-Output ('##' + $k + '=' + $result[$k]) } ^
} catch { ^
    Write-Output ('错误: ' + $_.Exception.Message) ^
} ^
" > "%DEBUG_FILE%"

:: 读取结果
if "%DEBUG_MODE%"=="1" ( type "%DEBUG_FILE%" )
for /f "tokens=1,2 delims==" %%a in ('type "%DEBUG_FILE%" ^| findstr "##"') do (set "%%a=%%b")
del /Q /F "%DEBUG_FILE%" 2>nul

:: 检查远程关机命令
:: call :TRIGGER

:: 添加时间检查
if !##curr_hour! GEQ 21 (
    call :DO_SHUTDOWN "晚上不允许使用电脑"
    exit /b
)
if !##curr_hour! LSS 8 (
    call :DO_SHUTDOWN "早上8点前不允许使用电脑"
    exit /b
)

:: 设置节假日缓存文件
set "HOLIDAY_CACHE=%BASE_PATH%_holiday.txt"

:: 获取节假日数据
call :GET_HOLIDAY_DATA
if !ERRORLEVEL! NEQ 0 (
    :: 如果API调用失败，使用缓存数据
    if exist "%HOLIDAY_CACHE%" (
        for /f "tokens=1,2 delims==" %%a in ('type "%HOLIDAY_CACHE%"') do set "%%a=%%b"
    ) else (
        :: 默认节假日列表（格式：MMDD）
        set "HOLIDAYS=0101 0102 0103 0405 0501 0502 0503 0504 0505 0624 0625 0626 1001 1002 1003 1004 1005 1006 1007"
    )
)

:: 获取当前日期的月和日
for /f "tokens=1-3 delims=/ " %%a in ("%DATE%") do (
    set "curr_date=%%b%%c"
)

:: 检查是否为法定节假日
echo.!HOLIDAYS! | findstr /i "!curr_date!" >nul
if !ERRORLEVEL! EQU 0 (
    :: 是法定节假日，跳过工作日限制
    goto :BYPASS_WORKDAY
)

if !##weekday! LSS 5 (
    if !##curr_hour! GEQ 17 (
        call :DO_SHUTDOWN "工作日不允许使用电脑"
        exit /b
    )
)

:BYPASS_WORKDAY

:: 检查关机条件
if !##rest_elapsed! LSS %REST_MINUTES% (
    call :DO_SHUTDOWN "距离上次关机未满%REST_MINUTES%分钟，立刻关机"
    exit /b
)
:: 检查开机时长
if !##play_elapsed! GEQ %PLAY_MINUTES% (
    echo %DATE:~0,10% %TIME% > "%REST_FILE%"
    call :DO_SHUTDOWN "开机时间超过%PLAY_MINUTES%分钟，立刻关机"
    exit /b
)
:: 结束
goto :END

:: 以下是函数
:DISABLE
shutdown /a
echo %DATE:~0,10% %TIME% > "%DISABLE_FILE%"
call :LOG "已禁用定时关机功能"
exit /b 0

:RESET
shutdown /a
del /Q /F "%PLAY_FILE%" "%REST_FILE%" "%DISABLE_FILE%"
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
    echo.
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
for /f "delims=" %%a in ('curl.exe -fssSL -X POST %URL_HOST%/trigger') do set "RESPONSE=%%a"
echo.!RESPONSE! | findstr /i "play" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    exit /b 1
)
echo.!RESPONSE! | findstr /i "rest" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
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

:UPGRADE
:: 下载最新版本的脚本
curl.exe -Lo "%~f0.new" "https://gitee.com/xiagw/deploy.sh/raw/main/lib/utils/child.cmd"
if %ERRORLEVEL% NEQ 0 (
    call :LOG "下载新版本失败"
    del /F /Q "%~f0.new" 2>nul
    exit /b 1
)
:: 替换旧文件
move /Y "%~f0.new" "%~f0" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    call :LOG "更新文件失败"
    del /F /Q "%~f0.new" 2>nul
    exit /b 1
)
call :LOG "更新成功完成"
exit /b 0

:GET_HOLIDAY_DATA
:: 使用提莫API获取节假日数据
for /f "tokens=1-3 delims=/" %%a in ("%DATE%") do (
    set "curr_year=%%a"
)

:: 检查缓存文件是否存在且为当前年份的数据
if exist "%HOLIDAY_CACHE%" (
    for /f "tokens=1,2 delims==" %%i in ('type "%HOLIDAY_CACHE%"') do (
        if "%%i"=="YEAR" set "cache_year=%%j"
    )
    if "%cache_year%"=="%curr_year%" (
        for /f "tokens=1,2 delims==" %%i in ('type "%HOLIDAY_CACHE%"') do (
            if "%%i"=="HOLIDAYS" set "HOLIDAYS=%%j"
        )
        if defined HOLIDAYS exit /b 0
    )
)

:: 如果缓存不存在或已过期，则调用API获取新数据
:: https://github.com/NateScarlet/holiday-cn
powershell -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -Command ^
"try { ^
    $year = '%curr_year%'; ^
    $apiUrl = 'http://timor.tech/api/holiday/year/' + $year; ^
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get; ^
    if ($response.code -eq 0) { ^
        $holidayList = @(); ^
        foreach ($property in $response.holiday.PSObject.Properties) { ^
            $date = $property.Name; ^
            $info = $property.Value; ^
            if ($info.holiday -eq $true) { ^
                $mmdd = $date.Replace('-', ''); ^
                $holidayList += $mmdd; ^
            } ^
        } ^
        $holidays = [string]::Join(' ', $holidayList); ^
        Set-Content -Path '%HOLIDAY_CACHE%' -Value ('YEAR=' + '%curr_year%') -Force; ^
        Add-Content -Path '%HOLIDAY_CACHE%' -Value ('HOLIDAYS=' + $holidays) -Force; ^
        Write-Output ('HOLIDAYS=' + $holidays); ^
        exit 0; ^
    } else { ^
        Write-Error ('API返回错误: ' + $response.message); ^
        exit 1; ^
    } ^
} catch { ^
    Write-Error ('请求失败: ' + $_.Exception.Message); ^
    exit 1; ^
}^
" > "%DEBUG_FILE%"

if "%DEBUG_MODE%"=="1" ( type "%DEBUG_FILE%" )
for /f "tokens=1,2 delims==" %%a in ('type "%DEBUG_FILE%"') do (set "%%a=%%b")
del /Q /F "%DEBUG_FILE%" 2>nul

exit /b !ERRORLEVEL!

:END
exit /b 0
