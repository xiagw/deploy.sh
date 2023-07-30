@echo off
REM schtasks /Create /SC MINUTE /TN child /NP /RU SYSTEM /TR C:\Users\xia\child.bat

set me_path=%~dp0
set ps_file=%me_path%child.ps1
set log_file=%me_path%child.log
set play_file=%me_path%child.play
set rest_file=%me_path%child.rest
set disable_file=%me_path%child.disable
set force_file=%me_path%child.force

if "%1"=="c" goto :cancel
if "%1"=="cancel" goto :cancel

if "%1"=="d" goto :disable
if "%1"=="disable" goto :disable

if "%1"=="f" goto :force
if "%1"=="force" goto :force

if "%1"=="r" goto :revert
if "%1"=="revert" goto :revert

rem diable shutdown
if exist %disable_file% goto :END

goto :start

rem homework mode, week 1-4, after 19:30, always shutdown
if %TIME:~0,2%%TIME:~3,2% GTR 1930 (
    if not exist %force_file% (
        if "%DATE:~11%"=="周一" (goto :poweroff)
        if "%DATE:~11%"=="周二" (goto :poweroff)
        if "%DATE:~11%"=="周三" (goto :poweroff)
        if "%DATE:~11%"=="周四" (goto :poweroff)
    )
)

:start
set posh_exe=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
set posh_opt=-NonInteractive -WindowStyle Hidden -NoProfile -NoLogo -executionpolicy remotesigned
set posh_file=-file "%ps_file%"
%posh_exe% %posh_opt% %posh_file%
goto :END

:writelog
echo. >>%log_file%
goto :END

:poweroff
shutdown.exe /s /t 30 /f
goto :END

:cancel
shutdown /a
del /f /q %play_file% %rest_file%
goto :END

:disable
echo. >%disable_file%
shutdown /a
del /f /q %play_file% %rest_file%
goto :END

:force
echo. >%force_file%
shutdown /a
del /f /q %play_file% %rest_file%
goto :END

:revert
del /f /q %disable_file% %force_file%
goto :END

:END
