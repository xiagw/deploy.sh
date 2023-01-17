@echo off

:: setup network
echo Prepare the network...
wpeinit

ipconfig

:: mount network share
set IP1=192.168.1.154
set IP2=192.168.5.154
set IP3=192.168.2.1
set IP4=192.168.3.1

for %%I in (%IP1%,%IP2%,%IP3%,%IP4%) do (
    ping -n 2 %%I >nul
    if errorlevel 1 (
        echo network error %%I
    ) else (
        echo network success %%I
        net use Z: \\%%I\win10
        net use Y: \\%%I\win7
        goto :menu
    )
)

:: install menu
:menu
cls
echo    :: Install Menu
echo.
echo        1. Install Windows 10
echo        2. Install Windows 7
echo.
echo    :: Type a 'number' and press ENTER
echo.

set /P menu=
if %menu%==1 goto :win10
if %menu%==2 goto :win7
if %menu%==exit (
    goto EOF
) else (
    cls
    goto :menu
)

:win10
Z:\setup.exe
goto :END

:win7
Y:\setup.exe
goto :END

:END
pause