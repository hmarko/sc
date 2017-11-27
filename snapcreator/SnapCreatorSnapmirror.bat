@echo off
echo Parameters:
echo Profile %1
echo Config %2

C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -file c:\scripts\snapcreator\SnapCreatorSnapmirror.ps1 -profile %1 -config %2 
exit %ERRORLEVEL%