@echo off
rem uwh starten - ohne dass PowerShell die Ausfuehrung verweigert.
rem Bei Fehlern wartet uwh selbst auf eine Taste, bevor das Fenster schliesst.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uwh.ps1" %*
