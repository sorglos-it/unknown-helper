<#
    uwh einrichten.

    Einzeiler in PowerShell:
        irm https://raw.githubusercontent.com/sorglos-it/uwh/main/install.ps1 | iex

    Es wird kein git gebraucht. uwh landet unter:
        %LOCALAPPDATA%\Programs\uwh
#>
[CmdletBinding()]
param(
    [string]$Ziel,
    [switch]$KeinStart
)

$ErrorActionPreference = 'Stop'

$Zip = 'https://codeload.github.com/sorglos-it/uwh/zip/refs/heads/main'

if (-not $Ziel) { $Ziel = Join-Path $env:LOCALAPPDATA 'Programs\uwh' }

Write-Host ''
Write-Host '  uwh - unknown windows helper' -ForegroundColor Cyan
Write-Host '  ----------------------------' -ForegroundColor DarkGray
Write-Host ''

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host '  Es wird mindestens Windows PowerShell 5.1 gebraucht.' -ForegroundColor Red
    exit 1
}

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
} catch { }

$tmp = Join-Path $env:TEMP ('uwh-setup-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$zipFile = "$tmp.zip"

try {
    Write-Host '  Lade uwh herunter...'
    Invoke-WebRequest -Uri $Zip -OutFile $zipFile -UseBasicParsing -ErrorAction Stop

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $tmp)

    $quelle = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
    if (-not $quelle) { throw 'Das Archiv war leer.' }

    if (-not (Test-Path $Ziel)) { New-Item -ItemType Directory -Path $Ziel -Force | Out-Null }

    foreach ($item in Get-ChildItem -LiteralPath $quelle.FullName) {
        # Eigene Profile und Skripte bleiben bei einer Neuinstallation erhalten.
        if ($item.Name -eq 'custom' -and (Test-Path (Join-Path $Ziel 'custom'))) { continue }
        if ($item.PSIsContainer) {
            Copy-Item -LiteralPath $item.FullName -Destination $Ziel -Recurse -Force
        } else {
            Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Ziel $item.Name) -Force
        }
    }

    Write-Host "  Eingerichtet unter: $Ziel" -ForegroundColor Green

    # Verknuepfung auf dem Desktop, damit man es wiederfindet.
    try {
        $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'uwh.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $s = $shell.CreateShortcut($lnk)
        $s.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Ziel 'uwh.ps1')
        $s.WorkingDirectory = $Ziel
        $s.IconLocation = 'shell32.dll,165'
        $s.Description = 'uwh - Software auswaehlen und installieren'
        $s.Save()
        Write-Host '  Verknuepfung auf dem Desktop angelegt.' -ForegroundColor Green
    } catch {
        Write-Host '  Verknuepfung konnte nicht angelegt werden.' -ForegroundColor DarkGray
    }

    Write-Host ''
    if (-not $KeinStart) {
        Write-Host '  uwh startet...'
        Write-Host ''
        & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
            '-NoProfile' '-ExecutionPolicy' 'Bypass' '-File' (Join-Path $Ziel 'uwh.ps1')
    } else {
        Write-Host ('  Starten mit:  {0}' -f (Join-Path $Ziel 'uwh.ps1'))
        Write-Host ''
    }
} catch {
    Write-Host ''
    Write-Host "  Einrichtung fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    exit 1
} finally {
    Remove-Item -LiteralPath $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
