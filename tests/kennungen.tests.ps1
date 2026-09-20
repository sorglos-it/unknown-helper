# Prueft, ob es jede Paketkennung aus config.yaml wirklich gibt.
# Braucht winget und Internet und dauert ein bis zwei Minuten.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File tests\kennungen.tests.ps1
#
# Immer laufen lassen, wenn dem Katalog etwas hinzugefuegt wurde.
# Paketkennungen aendern sich: Hersteller benennen um, Pakete verschwinden.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
foreach ($lib in @('core', 'yaml', 'catalog', 'providers')) { . (Join-Path $root "lib\$lib.ps1") }

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

# --- winget und Microsoft Store ---
foreach ($e in @($catalog.Entries | Where-Object { $_.Provider -in @('winget', 'msstore') })) {
    $null = & $exe show --id $e.Id --exact --source $e.Provider `
                        --disable-interactivity --accept-source-agreements 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("  ok    {0,-18} {1}" -f $e.Key, $e.Id) -ForegroundColor DarkGreen
    } else {
        $fehler.Add(("{0}: '{1}' gibt es in der Quelle '{2}' nicht" -f $e.Key, $e.Id, $e.Provider))
        Write-Host ("  FEHL  {0,-18} {1}" -f $e.Key, $e.Id) -ForegroundColor Red
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

Write-Host ''
if ($fehler.Count -gt 0) {
    Write-Host '  Zu berichtigen in config.yaml:' -ForegroundColor Yellow
    foreach ($f in $fehler) { Write-Host "    - $f" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host '  Richtige Kennung finden mit:  winget search <name>' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

Write-Host '  Alle Kennungen in Ordnung.' -ForegroundColor Green
Write-Host ''
exit 0
