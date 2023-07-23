@echo off
REM schtasks /Create /SC MINUTE /TN child /NP /RU SYSTEM /TR C:\Users\xia\child.bat

set me_path=%~dp0
set ps_file=%me_path%\child.ps1
set log_file=%me_path%\child.log
set play_file=%me_path%\child.play
set rest_file=%me_path%\child.rest
set disable_file=%me_path%\child.disable
set force_file=%me_path%\child.force

if "%1"=="d" goto :disable
if "%1"=="disable" goto :disable

if "%1"=="f" goto :force
if "%1"=="force" goto :force

if "%1"=="r" goto :revert
if "%1"=="revert" goto :revert

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

rem diable shutdown
if exist %disable_file% goto :END

rem study mode, program with vscode, but no minecraft

rem homework mode, week 1-4, after 19:30, always shutdown
if %TIME:~0,2%%TIME:~3,2% GTR 1930 (
    if not exist %force_file% (
        if "%DATE:~11%"=="周一" (goto :poweroff)
        if "%DATE:~11%"=="周二" (goto :poweroff)
        if "%DATE:~11%"=="周三" (goto :poweroff)
        if "%DATE:~11%"=="周四" (goto :poweroff)
    )
)

rem # Check if it's time to rest
for %%a in ("%rest_file%") do (
    set "rest_file_time=%%~ta"
)
if exist %rest_file% (

)
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

rem # (Get-Date) - (gcim Win32_OperatingSystem).LastBootUpTime
rem #### play #####################################
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
