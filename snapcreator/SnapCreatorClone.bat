@echo off
echo Parameters:
echo Profile %1
echo Config %2
echo Snapshot %3
echo Clonename %4
echo NFSHOST %5
echo SPLIT %6
set JUNCTION=%7
if [%7]==[] set JUNCTION=*
echo JUNCTION %JUNCTION%

C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe  -ExecutionPolicy Bypass -file c:\scripts\snapcreator\SnapCreatorClone.ps1 -profile %1 -config %2 -snapshot %3 -clonename %4 -nfshosts %5 -split %6 -junction %JUNCTION%
exit %ERRORLEVEL%