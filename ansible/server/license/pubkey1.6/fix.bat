@echo off
echo Add dummy SIGN to license file...please wait...
setlocal enabledelayedexpansion

set "file=%1"
set "file_personal=temp_license.dat"
(
    for /f "tokens=*" %%i in (%file%) do (
        set s=%%i
		rem replace ) } with SIGN=....) }
        set "s=!s:) }= SIGN="^0000 1111 2222 3333 4444 5555 6666 7777 8888 9999 AAAA BBBB CCCC DDDD EEEE FFFF 0000 1111 2222 3333 4444 5555 6666 7777 8888 9999 AAAA BBBB CCCC DDDD") }!"
		set "s=!s:RK:0:0:1=RK:0:0:1 SIGN="^0000 1111 2222 3333 4444 5555 6666 7777 8888 9999 AAAA BBBB CCCC DDDD EEEE FFFF 0000 1111 2222 3333 4444 5555 6666 7777 8888 9999 AAAA BBBB CCCC DDDD"!"
        echo !s!
    )
)> %file_personal%

del %1
move %file_personal% %1