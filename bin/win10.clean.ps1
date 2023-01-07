# Disk Cleanup Using Powershell Scripts
# https://www.c-sharpcorner.com/blogs/disk-cleanup-using-powershell-scripts
##################################################################################
#DiskCleanUp
##################################################################################

##Variables####

$objShell=New-Object-ComObjectShell.Application
$objFolder=$objShell.Namespace(0xA)

$temp=get-ChildItem"env:\TEMP"
$temp2=$temp.Value

$WinTemp="C:\Windows\Temp\*"

#Removetempfileslocatedin"C:\Users\USERNAME\AppData\Local\Temp"
write-Host"RemovingJunkfilesin$temp2."-ForegroundColorMagenta
Remove-Item-Recurse"$temp2\*"-Force-Verbose

#EmptyRecycleBin#http://demonictalkingskull.com/2010/06/empty-users-recycle-bin-with-powershell-and-gpo/
write-Host"EmptyingRecycleBin."-ForegroundColorCyan
$objFolder.items()|%{remove-item$_.path-Recurse-Confirm:$false}

#RemoveWindowsTempDirectory
write-Host"RemovingJunkfilesin$WinTemp."-ForegroundColorGreen
Remove-Item-Recurse$WinTemp-Force

#6#RunningDiskCleanupTool
write-Host"Finallynow,RunningWindowsdiskCleanupTool"-ForegroundColorCyan
cleanmgr/sagerun:1|out-Null

$([char]7)
Sleep1
$([char]7)
Sleep1

write-Host "Clean Up Task Finished !!!"
#####EndoftheScript#####ad
