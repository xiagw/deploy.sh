@echo off
:: ============================================================
::  child.cmd - 定时限制儿童使用电脑
::
::  规则:
::    1) 晚间 21:00 - 次日 08:00 禁用
::    2) 工作日(周一-周四) 12:00 之后禁用
::    3) 单次使用达到 PLAY_MIN 分钟后关机
::    4) 距上次关机不足 REST_MIN 分钟内保持关机
::  节假日或存在 _bypass_workday.txt 时跳过规则 2
::
::  参数: 无 -> 主流程
::   debug | reset | upgrade | install | server | disable | bypass
::
::  性能: 主流程纯 CMD 时间戳结算, 不启动 PowerShell;
::        仅当天日期缓存过期时启动一次 PowerShell 取星期/节假日
:: ============================================================
setlocal EnableDelayedExpansion

set "SCRIPT_NAME=%~n0"
set "BASE_PATH=%~dp0%SCRIPT_NAME%"
set "LOGFILE=%BASE_PATH%.log"
set "STATE_FILE=%BASE_PATH%_state.txt"
set "DISABLE_FILE=%BASE_PATH%_disable.txt"
set "BYPASS_FILE=%BASE_PATH%_bypass_workday.txt"
set "DAILY_FILE=%BASE_PATH%_daily.txt"
set "HOLIDAY_CACHE=%BASE_PATH%_holiday.txt"
set "PLAY_MIN=60"
set "REST_MIN=90"
set "DELAY_SECONDS=90"
set "URL_PORT=8899"

echo.%1| findstr /i "^debug$ ^d$" >nul && set "DEBUG_MODE=1"
echo.%1| findstr /i "^reset$ ^r$" >nul && goto :RESET
echo.%1| findstr /i "^upgrade$ ^u$" >nul && goto :UPGRADE
echo.%1| findstr /i "^install$ ^i$" >nul && goto :INSTALL_TASK
echo.%1| findstr /i "^server$ ^s$" >nul && goto :START_SERVER
echo.%1| findstr /i "^disable$ ^x$" >nul && goto :DISABLE
echo.%1| findstr /i "^bypass$ ^bw$" >nul && goto :BYPASS_WORKDAY_CMD

if exist "%DISABLE_FILE%" ( exit /b 0 )

:: ============================================================
::  纯 CMD 取当前 HH:MM (去掉 %TIME% 前导空格)
:: ============================================================
set "NOW_RAW=%TIME: =0%"
if "%NOW_RAW%"=="" set "NOW_RAW=090000.00"
set "HOUR2=%NOW_RAW:~0,2%"
set "MINU2=%NOW_RAW:~3,2%"
if "%HOUR2%"=="24" set "HOUR2=00"
set /a HOUR=(1%HOUR2%-100)
set /a MINUTE=(1%MINU2%-100)
set /a NOW_MIN=%HOUR%*60+%MINUTE%

:: ============================================================
::  规则 1: 21:00-08:00 禁用 (纯 CMD)
:: ============================================================
if %HOUR% GEQ 21 ( call :DO_SHUTDOWN "晚间禁用时段" & exit /b 0 )
if %HOUR% LSS 8  ( call :DO_SHUTDOWN "早间禁用时段" & exit /b 0 )

:: ============================================================
::  每日缓存: 星期/是否节假日 (过期才启动 PowerShell)
:: ============================================================
call :ENSURE_DAILY

:: ============================================================
::  规则 2: 工作日 12:00 后禁用
:: ============================================================
if "%HOLIDAY%"=="1" goto :AFTER_WD
if exist "%BYPASS_FILE%" goto :AFTER_WD
if %WEEKDAY% LSS 5 (
    if %HOUR% GEQ 12 ( call :DO_SHUTDOWN "工作日下午禁用" & exit /b 0 )
)
:AFTER_WD

:: ============================================================
::  初始化/读取 状态文件 (单文件 两行 PLAY/REST)
:: ============================================================
if not exist "%STATE_FILE%" call :INIT_STATE
call :READ_STATE

:: ============================================================
::  计算 已用/休息 分钟数 (HH:MM -> 当日分钟)
:: ============================================================
set /a PLAY_REF=(1%PLAY_HH%-100)*60+(1%PLAY_MM%-100)
set /a REST_REF=(1%REST_HH%-100)*60+(1%REST_MM%-100)
set /a PLAY_ELAPSED=%NOW_MIN%-%PLAY_REF%
if %PLAY_ELAPSED% LSS 0 set /a PLAY_ELAPSED+=1440

set /a REST_ELAPSED=%NOW_MIN%-%REST_REF%
if %REST_ELAPSED% LSS 0 set /a REST_ELAPSED+=1440

:: ============================================================
::  规则 4: 关机冷却
:: ============================================================
if %REST_ELAPSED% LSS %REST_MIN% (
    call :DO_SHUTDOWN "距上次关机未满 %REST_MIN% 分钟"
    exit /b 0
)

:: 已用超过 REST_MIN 分钟视为新会话, 重置计时
if %PLAY_ELAPSED% GTR %REST_MIN% (
    set "PLAY_HH=%HOUR2%"
    set "PLAY_MM=%MINU2%"
    call :SAVE_STATE
    set "PLAY_ELAPSED=0"
)

:: ============================================================
::  规则 3: 单次使用限时
:: ============================================================
if %PLAY_ELAPSED% GEQ %PLAY_MIN% (
    set "REST_HH=%HOUR2%"
    set "REST_MM=%MINU2%"
    call :SAVE_STATE
    call :DO_SHUTDOWN "本次使用已满 %PLAY_MIN% 分钟"
    exit /b 0
)

if "%DEBUG_MODE%"=="1" (
    echo [debug] play=%PLAY_ELAPSED% rest=%REST_ELAPSED% wd=%WEEKDAY% hol=%HOLIDAY%
)
exit /b 0

:: ============================================================
::  ---- 每日缓存: 星期/节假日 ----
::  ============================================================
:ENSURE_DAILY
:: 当天缓存还存在且 TAG 匹配今天 -> 直接复用
call :TODAY
set "CACHE_TAG="
for /f "tokens=1,2 delims==" %%a in ('type "%DAILY_FILE%" 2^>nul') do (
    if "%%a"=="TAG" set "CACHE_TAG=%%b"
)
if "%CACHE_TAG%"=="%TODAY%" goto :READ_DAILY

:: 缓存过期 -> 启动一次 PowerShell
call :GEN_DAILY

:READ_DAILY
set "WEEKDAY=7"
set "HOLIDAY=0"
for /f "tokens=1,* delims==" %%a in ('type "%DAILY_FILE%" 2^>nul') do (
    if "%%a"=="WEEKDAY" set "WEEKDAY=%%b"
    if "%%a"=="HOLIDAY" set "HOLIDAY=%%b"
)
goto :eof

:TODAY
set "TODAY="
for /f "tokens=1-3 delims=/ " %%a in ("%DATE%") do set "TODAY=%%a%%b%%c"
goto :eof

:GEN_DAILY
:: 一次性 PowerShell: 取星期并同步节假日表; 失败时用内置默认节假日
powershell -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -Command ^
"$y=Get-Date; ^
$tag=$y.ToString('yyyy')+$y.ToString('MM')+$y.ToString('dd'); ^
$w=[int]$y.DayOfWeek; if($w -eq 0){$w=7}; ^
$mmdd=$y.ToString('MM')+$y.ToString('dd'); ^
$cache='%HOLIDAY_CACHE%'; ^
$holiday=''; ^
if(Test-Path $cache){ ^
  $h=''; ^
  foreach($ln in @(Get-Content $cache)){ ^
    if($ln -match '^YEAR=.+'){ $h=$ln.Substring(5).Trim() } ^
    if($ln -match '^LIST=.+'){ $holiday=$ln.Substring(5).Trim() } ^
  } ^
  if($h -ne $tag.Substring(0,4)){ $holiday='' } ^
} ^
if(-not $holiday){ ^
  try{ ^
    $r=Invoke-RestMethod -Uri ('http://timor.tech/api/holiday/year/'+$y.Year) -Method Get -TimeoutSec 8; ^
    if($r.code -eq 0){ ^
      $arr=@(); ^
      foreach($p in $r.holiday.PSObject.Properties){ if($p.Value.holiday -eq $true){ $arr+=$p.Name.Replace('-','') } } ^
      $holiday=$arr -join ' '; ^
      if($holiday){ Set-Content -Path $cache -Value ('YEAR='+$y.Year+[char]10+'LIST='+$holiday) -Encoding Default } ^
    } ^
  } catch { } ^
} ^
if(-not $holiday){ $holiday='0100 0101 0102 0103 0405 0501 0502 0503 0504 0505 0624 0625 0626 1001 1002 1003 1004 1005 1006 1007' }; ^
$is=0; if(($holiday -split ' ') -contains $mmdd){ $is=1 }; ^
Set-Content -Path '%DAILY_FILE%' -Value @('TAG='+$tag, 'WEEKDAY='+$w, 'HOLIDAY='+$is) -Encoding Default; ^
" >nul 2>&1
goto :eof

:: ============================================================
::  工具函数
::  ============================================================
:INIT_STATE
:: 首启: PLAY=现在, REST=现在-REST_MIN 分钟 (允许立即计时, 而非立刻关机)
set "PLAY_HH=%HOUR2%"
set "PLAY_MM=%MINU2%"
set /a RV=%NOW_MIN%-%REST_MIN%
if %RV% LSS 0 set /a RV+=1440
set /a RVH=%RV%/60
set /a RVM=%RV% %% 60
if %RVH% LSS 10 set "RVH=0%RVH%"
if %RVM% LSS 10 set "RVM=0%RVM%"
set "REST_HH=%RVH%"
set "REST_MM=%RVM%"
call :SAVE_STATE
goto :eof
:READ_STATE
set "PLAY_HH="
set "PLAY_MM="
set "REST_HH="
set "REST_MM="
for /f "tokens=1,2,3 delims==:" %%A in ('type "%STATE_FILE%" 2^>nul') do (
    if "%%A"=="PLAY" set "PLAY_HH=%%B" & set "PLAY_MM=%%C"
    if "%%A"=="REST" set "REST_HH=%%B" & set "REST_MM=%%C"
)
if "%PLAY_HH%"=="" set "PLAY_HH=%HOUR2%"
if "%PLAY_MM%"=="" set "PLAY_MM=%MINU2%"
if "%REST_HH%"=="" set "REST_HH=%HOUR2%"
if "%REST_MM%"=="" set "REST_MM=%MINU2%"
goto :eof

:SAVE_STATE
>  "%STATE_FILE%" echo PLAY=%PLAY_HH%:%PLAY_MM%
>> "%STATE_FILE%" echo REST=%REST_HH%:%REST_MM%
goto :eof

:LOG
echo [%DATE% %TIME%] %~1 >> "%LOGFILE%"
goto :eof

:DO_SHUTDOWN
call :LOG "关机: %~1"
if "%DEBUG_MODE%"=="1" echo [debug] shutdown skip: %~1 & goto :eof
shutdown /s /t %DELAY_SECONDS% /c "%~1"
goto :eof

:: ============================================================
::  ---- 管理命令 ----
::  ============================================================
:DISABLE
shutdown /a
> "%DISABLE_FILE%" echo %DATE% %TIME%
call :LOG "已禁用脚本"
exit /b 0

:BYPASS_WORKDAY_CMD
> "%BYPASS_FILE%" echo %DATE% %TIME%
call :LOG "已临时绕过工作日限制"
exit /b 0

:RESET
shutdown /a
del /Q /F "%STATE_FILE%" "%DISABLE_FILE%" 2>nul
call :LOG "已重置计时"
exit /b 0

:INSTALL_TASK
schtasks /Create /NP /TN "%SCRIPT_NAME%" /TR "\"%~f0\"" /SC minute /MO 1 /F /RU SYSTEM >nul 2>&1
if %ERRORLEVEL% EQU 0 ( call :LOG "计划任务已创建" ) else ( call :LOG "计划任务创建失败" )
exit /b 0

:UPGRADE
curl.exe -Lo "%~f0.new" "https://gitee.com/xiagw/deploy.sh/raw/main/lib/utils/child.cmd"
if %ERRORLEVEL% NEQ 0 ( call :LOG "升级下载失败" & goto :eof )
move /Y "%~f0.new" "%~f0" >nul 2>&1
call :LOG "升级完成"
exit /b 0

:START_SERVER
powershell -NoProfile -ExecutionPolicy Bypass -Command "& {$l=New-Object System.Net.HttpListener; $l.Prefixes.Add('http://+:%URL_PORT%/'); $l.Start(); Write-Host 'listening :%URL_PORT%'; while($l.IsListening){$c=$l.GetContext(); if($c.Request.Url.LocalPath -eq '/shutdown'){ shutdown /s /t 90; break }; $c.Response.Close()}}"
exit /b 0

:END
exit /b 0