@echo off

REM GBK编码，CRLF换行，保留此行注释
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

echo.%1| findstr /i "^debug$ ^d$" >nul && set "DEBUG_MODE=1"
echo.%1| findstr /i "^reset$ ^r$" >nul && goto :RESET
echo.%1| findstr /i "^install$ ^i$" >nul && goto :INSTALL_TASK

:: 获取当前时间信息，处理前导空格和确保24小时制
for /f "tokens=1 delims=:" %%a in ('time /t') do (
    set "CURR_HOUR=%%a"
)
set "CURR_HOUR=%CURR_HOUR: =%"
if %CURR_HOUR% LSS 10 set "CURR_HOUR=0%CURR_HOUR%"

:: 获取当前星期几 (1-7, 其中1是周一)
if "%DATE:~11%"=="周一" set "WEEKDAY=1"
if "%DATE:~11%"=="周二" set "WEEKDAY=2"
if "%DATE:~11%"=="周三" set "WEEKDAY=3"
if "%DATE:~11%"=="周四" set "WEEKDAY=4"
if "%DATE:~11%"=="周五" set "WEEKDAY=5"
if "%DATE:~11%"=="周六" set "WEEKDAY=6"
if "%DATE:~11%"=="周日" set "WEEKDAY=7"

if "%DEBUG_MODE%"=="1" (
    call :LOG "DEBUG模式: 当前时间=%CURR_HOUR%"
    call :LOG "DEBUG模式: 当前星期几=%WEEKDAY%"
    call :LOG "DEBUG模式: 不检查时间限制"
) else (
    call :CHECK_TIME_LIMITS
)

:: 如果启动时间文件不存在，先创建
if not exist "%PLAY_FILE%" ( echo %DATE% %TIME% > "%PLAY_FILE%" )

:: 如果关机时间文件不存在，先创建（设置为启动时间的120分钟前）
if not exist "%REST_FILE%" (
    powershell -command "$startup = Get-Date (Get-Content '%PLAY_FILE%'); $shutdown = $startup.AddMinutes(-120); $shutdown.ToString('yyyy/MM/dd HH:mm:ss.ff')" > "%REST_FILE%"
)

:: 执行所有时间检查
powershell -command "$error.clear(); try { $result = @{}; $now = Get-Date; if(Test-Path '%REST_FILE%') { $shutdown = Get-Date (Get-Content '%REST_FILE%'); $result.rest_minutes = [Math]::Round(($now - $shutdown).TotalMinutes) }; if(Test-Path '%PLAY_FILE%') { $startup = Get-Date (Get-Content '%PLAY_FILE%'); $result.play_minutes = [Math]::Round(($now - $startup).TotalMinutes); if(Test-Path '%REST_FILE%') { $result.need_update = if($startup -gt $shutdown) { '0' } else { '1' } } }; foreach($k in $result.Keys) { Write-Output ('##' + $k + '=' + $result[$k]) } } catch { Write-Output ('错误: ' + $_.Exception.Message) }" > "%DEBUG_FILE%"

:: 读取结果
for /f "tokens=1,2 delims==" %%a in ('type "%DEBUG_FILE%" ^| findstr "##"') do (
    set "%%a=%%b"
    call :LOG "设置变量 %%a=%%b"
)
del "%DEBUG_FILE%" 2>nul

:: 更新启动时间
if !##need_update! EQU 1 (
    echo %DATE% %TIME% > "%PLAY_FILE%" || (
        call :LOG "无法更新启动时间文件"
        exit /b 1
    )
)

:: 检查关机条件
if !##rest_minutes! LSS %REST_MINUTES% (
    call :DO_SHUTDOWN "距离上次关机未满%REST_MINUTES%分钟"
    exit /b
)

:: 检查开机时长
if !##play_minutes! GEQ %PLAY_MINUTES% (
    echo %DATE% %TIME% > "%REST_FILE%"
    call :DO_SHUTDOWN "开机时间超过%PLAY_MINUTES%分钟"
    exit /b
)
:: 结束
goto :END

:: 以下是函数
:CHECK_TIME_LIMITS
:: 检查是否在允许的时间范围内
:: 检查21:00-08:00时间段
if %CURR_HOUR% GEQ %WORK_HOUR_21% (
    call :DO_SHUTDOWN "现在是%WORK_HOUR_21%点后"
    exit /b
)
if %CURR_HOUR% LSS %WORK_HOUR_8% (
    call :DO_SHUTDOWN "现在是%WORK_HOUR_8%点前"
    exit /b
)
:: 检查工作日17:00后限制
if %WEEKDAY% LEQ 5 (
    if %CURR_HOUR% GEQ %WORK_HOUR_17% (
        call :DO_SHUTDOWN "现在是工作日%WORK_HOUR_17%点后"
        exit /b
    )
)
exit /b

:RESET
shutdown /a
del /Q /F "%PLAY_FILE%"
del /Q /F "%REST_FILE%"
goto :END

:: 如果有参数"install"，则创建计划任务
:INSTALL_TASK
schtasks /query /tn "%SCRIPT_NAME%" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    :: 使用当前用户账户创建任务，不使用系统账户
    schtasks /create /tn "%SCRIPT_NAME%" /tr "\"%~f0\"" /sc minute /mo 1 /f /ru "%USERNAME%" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        call :LOG "成功创建计划任务"
    ) else (
        call :LOG "创建计划任务失败"
        exit /b 1
    )
) else (
    call :LOG "计划任务已存在"
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
shutdown /s /t 30 /c "%~1，系统将在30秒后关机" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    call :LOG "执行关机命令失败"
    exit /b 1
)
exit /b 0

:: 定义一个记录日志的函数
:LOG
echo [%DATE% %TIME%] %~1
echo [%DATE% %TIME%] %~1 >> "%LOGFILE%"
exit /b 0

:END
exit /b 0