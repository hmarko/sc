@echo off
echo Parameters:
echo Profile %1
echo Config %2
echo Clonename %3

C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe  -ExecutionPolicy Bypass -file c:\scripts\SnapCreator\SnapCreatorUmountClone.ps1 -profile %1 -config %2 -clonename %3 
exit %ERRORLEVEL%