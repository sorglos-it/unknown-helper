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

# Aus einer technischen Meldung etwas machen, mit dem man etwas anfangen kann.
function Get-Klartext {
    param($Fehler)

    $text = [string]$Fehler.Exception.Message
    $status = ''
    if ($Fehler.Exception -is [Net.WebException] -and $Fehler.Exception.Response) {
        $status = [string][int]$Fehler.Exception.Response.StatusCode
    }

    if ($status -eq '404' -or $text -match '\(404\)') {
        return @(
            'uwh wurde unter der angegebenen Adresse nicht gefunden.'
            'Moegliche Ursachen:'
            '  - das Repository ist (noch) nicht oeffentlich'
            '  - die Adresse im Skript stimmt nicht mehr'
        )
    }
    if ($status -eq '403' -or $status -eq '401') {
        return @('Der Zugriff wurde verweigert. Das Repository ist vermutlich nicht oeffentlich.')
    }
    if ($text -match 'Remotename|remote name|NameResolution|konnte nicht aufgel') {
        return @('Keine Verbindung zum Internet, oder der Server ist nicht erreichbar.')
    }
    if ($text -match 'SSL|TLS|Vertrauensstellung|trust relationship') {
        return @(
            'Die gesicherte Verbindung kam nicht zustande.'
            'Meist liegt das an einer Firewall oder an einem Virenscanner, der mitliest.'
        )
    }
    if ($text -match 'Zugriff verweigert|Access to the path|UnauthorizedAccess') {
        return @(
            'Es durfte nicht in den Zielordner geschrieben werden.'
            'Laeuft uwh gerade? Dann bitte erst schliessen.'
        )
    }
    return @('Bitte Internetverbindung pruefen und es noch einmal versuchen.')
}

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

    # Vorhandene Profile bleiben bei einer Neuinstallation erhalten.
    $auslassen = @()
    if (Test-Path (Join-Path $Ziel 'custom')) { $auslassen = @('custom') }

    # Copy-Item -Recurse wuerde einen vorhandenen Zielordner verschachteln.
    function Kopiere-Baum {
        param([string]$Von, [string]$Nach, [string[]]$Aus = @())
        if (-not (Test-Path -LiteralPath $Nach)) {
            New-Item -ItemType Directory -Path $Nach -Force | Out-Null
        }
        foreach ($i in Get-ChildItem -LiteralPath $Von -Force) {
            if ($Aus -contains $i.Name) { continue }
            $z = Join-Path $Nach $i.Name
            if ($i.PSIsContainer) { Kopiere-Baum $i.FullName $z } 
            else { Copy-Item -LiteralPath $i.FullName -Destination $z -Force }
        }
    }
    Kopiere-Baum $quelle.FullName $Ziel $auslassen

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
    Write-Host "  Einrichtung fehlgeschlagen." -ForegroundColor Red
    Write-Host ''
    foreach ($zeile in (Get-Klartext $_)) { Write-Host "  $zeile" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host "  Technische Meldung: $($_.Exception.Message)" -ForegroundColor DarkGray
    Write-Host ''
    exit 1
} finally {
    Remove-Item -LiteralPath $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
