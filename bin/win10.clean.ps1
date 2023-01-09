# Disk Cleanup Using Powershell Scripts
# https://www.c-sharpcorner.com/blogs/disk-cleanup-using-powershell-scripts
##################################################################################
# DiskCleanUp
##################################################################################

## Variables ####

$objShell = New-Object -ComObject Shell.Application
$objFolder = $objShell.Namespace(0xA)

$temp = get-ChildItem "env:\TEMP"
$temp2 = $temp.Value

$WinTemp = "C:\Windows\Temp\*"

# Remove temp files located in "C:\Users\USERNAME\AppData\Local\Temp"
write-Host "Removing Junk files in $temp2." -ForegroundColor Magenta
Remove-Item -Recurse  "$temp2\*" -Force -Verbose

# Empty Recycle Bin # http://demonictalkingskull.com/2010/06/empty-users-recycle-bin-with-powershell-and-gpo/
write-Host "Emptying Recycle Bin." -ForegroundColor Cyan
$objFolder.items() | %{ remove-item $_.path -Recurse -Confirm:$false}

# Remove Windows Temp Directory
write-Host "Removing Junk files in $WinTemp." -ForegroundColor Green
Remove-Item -Recurse $WinTemp -Force

#6# Running Disk Clean up Tool
write-Host "Finally now , Running Windows disk Clean up Tool" -ForegroundColor Cyan
cleanmgr /sagerun:1 | out-Null

$([char]7)
Sleep 1
$([char]7)
Sleep 1

write-Host "Clean Up Task Finished !!!"
##### End of the Script ##### ad
