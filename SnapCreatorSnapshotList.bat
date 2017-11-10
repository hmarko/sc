@echo off
echo SnapCreatorSnapshotList Parameters:
echo profile %1
echo config %2
set snapshot=%3
if [%3]==[] set snapshot=*
echo snapshot %snapshot%

C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe  -ExecutionPolicy Bypass -file c:\scripts\snapcreator\SnapCreatorSnapshotList.ps1 -profile %1 -config %2 -snapshot %snapshot%
rem exit %ERRORLEVEL%