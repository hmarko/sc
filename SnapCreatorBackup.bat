@echo off
echo Parameters:
echo Profile %1
echo Config %2
echo Policy %3

C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -file C:\Scripts\SnapCreator\SnapCreatorBackup.ps1 -profile %1 -config %2 -policy %3 
exit %ERRORLEVEL%