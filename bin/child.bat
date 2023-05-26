@echo off
REM schtasks /Create /SC MINUTE /TN child /NP /RU SYSTEM /TR C:\Applications\child.bat

set me_path=C:\applications

if "%1"=="c" goto :cancel
if "%1"=="cancel" goto :cancel

if "%1"=="a" goto :always
if "%1"=="always" goto :always

if "%1"=="r" goto :revert
if "%1"=="revert" goto :revert

:start
set posh_exe=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
set posh_opt=-NonInteractive -WindowStyle Hidden -NoProfile -NoLogo -executionpolicy remotesigned
set posh_file=-file "%me_path%\child.ps1"
%posh_exe% %posh_opt% %posh_file%
goto :END

:cancel
shutdown /a
del /f /q %me_path%\child.play %me_path%\child.rest
shutdown /a
goto :END

:always
echo. >%me_path%\child.cancel
goto :END

:revert
del /f /q %me_path%\child.cancel
goto :END

:END

