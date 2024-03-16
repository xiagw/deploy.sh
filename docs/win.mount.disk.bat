@echo off
REM 挂载目录为盘符

set count=3
echo.
echo 注意： 三次输入错误将退出.
echo.

:get_pass
set /p mima=请输入密码：
if \"%mima%\"==\"1234\" goto :set_drive
set /a count-=1
if \"%count%\"==\"0\" cls&echo.&echo =没密码无法进入=&echo.&pause&echo.&exit
cls&echo.&echo 你还有 %count% 次机会&echo.&goto :get_pass

:set_drive
cls&echo.
echo= 密码正确，放行 =
md D:\RECYCLED\UDrives.{25336920-03F9-11CF-8FD0-00AA00686F13}>NUL
if exist M:\NUL goto :remove
subst M: D:\RECYCLED\UDrives.{25336920-03F9-11CF-8FD0-00AA00686F13}
start M:\
goto :end

:remove
subst /D M:
goto :end

:end
echo.&pause&exit.