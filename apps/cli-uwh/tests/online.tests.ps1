# Pruefungen, die Internet brauchen: gibt es jede Paketkennung aus
# assets\catalog.yaml wirklich, und haelt der Direkt-Download seine Zusagen.
# Dauert ein bis zwei Minuten.
#
# Aufruf aus apps\cli-uwh:  powershell -ExecutionPolicy Bypass -File tests\online.tests.ps1
#
# Immer laufen lassen, wenn dem Katalog etwas hinzugefuegt wurde.
# Paketkennungen aendern sich: Hersteller benennen um, Pakete verschwinden.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
foreach ($lib in @('core', 'yaml', 'lang', 'repos', 'catalog', 'providers')) { . (Join-Path $root "classes\$lib.ps1") }
Set-UwhLanguage 'de'
Set-UwhLogFile (Join-Path $env:TEMP 'uwh-online.log')

$exe = Get-UwhWinget
if (-not $exe) {
    Write-Host ''
    Write-Host '  winget fehlt - Pruefung nicht moeglich.' -ForegroundColor Yellow
    Write-Host ''
    exit 2
}

$catalog = Get-UwhCatalog
$fehler = New-Object System.Collections.Generic.List[string]

Write-Host ''
Write-Host 'Kennungen' -ForegroundColor Cyan

# --- winget und Microsoft Store - jede Kennung, auch die je Sprache ---
foreach ($e in @($catalog.Entries | Where-Object { $_.Provider -in @('winget', 'msstore') })) {
    foreach ($id in @($e.Ids)) {
        $null = & $exe show --id $id --exact --source $e.Provider `
                            --disable-interactivity --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host ("  ok    {0,-18} {1}" -f $e.Key, $id) -ForegroundColor DarkGreen
        } else {
            $fehler.Add(("{0}: '{1}' gibt es in der Quelle '{2}' nicht" -f $e.Key, $id, $e.Provider))
            Write-Host ("  FEHL  {0,-18} {1}" -f $e.Key, $id) -ForegroundColor Red
        }
    }
}

# --- Windows-Funktionen und optionale Komponenten ---
# Get-WindowsOptionalFeature und Get-WindowsCapability brauchen
# Administratorrechte. Ohne sie wird hier nichts behauptet.
$systemEintraege = @($catalog.Entries | Where-Object { $_.Provider -in @('feature', 'capability') })

if (-not (Test-UwhAdmin)) {
    Write-Host ''
    Write-Host ("  {0} Windows-Eintraege uebersprungen - dafuer braucht es Administratorrechte." -f $systemEintraege.Count) -ForegroundColor DarkYellow
    Write-Host '  Vollstaendig pruefen: dieses Fenster als Administrator neu oeffnen.' -ForegroundColor DarkGray
} else {
    foreach ($e in $systemEintraege) {
        $gefunden = $false
        $grund = ''
        try {
            if ($e.Provider -eq 'feature') {
                $null = Get-WindowsOptionalFeature -Online -FeatureName $e.Id -ErrorAction Stop
            } else {
                $null = Get-WindowsCapability -Online -Name $e.Id -ErrorAction Stop
            }
            $gefunden = $true
        } catch {
            $grund = $_.Exception.Message
        }

        if ($gefunden) {
            Write-Host ("  ok    {0,-18} {1}" -f $e.Key, $e.Id) -ForegroundColor DarkGreen
        } else {
            $fehler.Add(("{0}: '{1}' ist diesem Windows unbekannt - {2}" -f $e.Key, $e.Id, $grund))
            Write-Host ("  FEHL  {0,-18} {1}" -f $e.Key, $e.Id) -ForegroundColor Red
        }
    }
}

# ------------------------------------------------------------------
# Direkt-Download: die Pruefsumme muss halten, was sie verspricht
# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Direkt-Download' -ForegroundColor Cyan

function Neuer-UrlEintrag {
    param([string]$Url, [string]$Sha256)
    [pscustomobject]@{
        Key = 'test'; Name = 'Test'; Description = ''; Category = ''
        Provider = 'url'; Id = ''; Scope = 'machine'
        Url = $Url; Sha256 = $Sha256; SilentArgs = '/S'; File = ''
        BaseDir = $root; Actions = @(); Admin = $true
        Reboot = ''; Recommended = $false; Note = ''
    }
}

function Pruefe {
    param([string]$Name, [bool]$Erfuellt, [string]$Erhalten)
    if ($Erfuellt) {
        Write-Host ("  ok    {0}" -f $Name) -ForegroundColor DarkGreen
    } else {
        $fehler.Add("$Name - erhalten: $Erhalten")
        Write-Host ("  FEHL  {0}" -f $Name) -ForegroundColor Red
    }
}

$vorher = @(Get-ChildItem -Path $env:TEMP -Filter 'uwh-*' -File -ErrorAction SilentlyContinue).Count

# Falsche Pruefsumme: Ablehnung, BEVOR irgendetwas ausgefuehrt wird.
$r = Invoke-UwhUrl (Neuer-UrlEintrag 'https://example.com/' ('0' * 64)) 'install'
Pruefe 'Falsche Pruefsumme wird abgelehnt' `
       ($r.Status -eq 'fehler' -and $r.Message -like '*Prüfsumme*') "$($r.Status) / $($r.Message)"

# Unerreichbare Adresse: sauberer Fehler statt Absturz.
$r2 = Invoke-UwhUrl (Neuer-UrlEintrag 'https://gibtesnicht.invalid/setup.exe' ('0' * 64)) 'install'
Pruefe 'Unerreichbare Adresse meldet einen Fehler' ($r2.Status -eq 'fehler') $r2.Status

# Kein https: es darf gar nicht erst geladen werden.
$r3 = Invoke-UwhUrl (Neuer-UrlEintrag 'http://example.com/setup.exe' '') 'install'
Pruefe 'Ohne https wird nichts geladen' `
       ($r3.Status -eq 'fehler' -and $r3.Message -like '*https*') "$($r3.Status) / $($r3.Message)"

# Nichts darf im Zwischenspeicher liegenbleiben.
$nachher = @(Get-ChildItem -Path $env:TEMP -Filter 'uwh-*' -File -ErrorAction SilentlyContinue).Count
Pruefe 'Keine Datei im Zwischenspeicher zurueckgelassen' ($nachher -le $vorher) "$vorher -> $nachher"

# ------------------------------------------------------------------

Write-Host ''
if ($fehler.Count -gt 0) {
    Write-Host '  Nicht in Ordnung:' -ForegroundColor Yellow
    foreach ($f in $fehler) { Write-Host "    - $f" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host '  Richtige Paketkennung finden mit:  winget search <name>' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

Write-Host '  Alles in Ordnung.' -ForegroundColor Green
Write-Host ''
exit 0
