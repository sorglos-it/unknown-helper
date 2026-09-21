@echo off
rem uwh starten - ohne dass PowerShell die Ausfuehrung verweigert.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uwh.ps1" %*
if errorlevel 1 pause
