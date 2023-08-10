@echo off
REM ¹ÒÔØÄ¿Â¼ÎªÅÌ·û

md D:\RECYCLED\UDrives.{25336920-03F9-11CF-8FD0-00AA00686F13}>NUL

if exist M:\NUL goto delete

subst M: D:\RECYCLED\UDrives.{25336920-03F9-11CF-8FD0-00AA00686F13}
start M:\

goto end

:delete
subst /D M:

:end