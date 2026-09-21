# Prueft Einrichtung und Selbstaktualisierung von Anfang bis Ende.
#
# Beides laeuft sonst nur gegen GitHub und waere damit nicht pruefbar. Hier
# wird ein Archiv gebaut, das genauso aussieht wie das von GitHub, und lokal
# ausgeliefert. Es wird nichts heruntergeladen, nichts installiert und keine
# Verknuepfung angelegt.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File tests\einrichtung.tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sandkasten = Join-Path $env:TEMP ('uwh-einr-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $sandkasten -Force | Out-Null

$script:Pass = 0
$script:Fail = 0

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Pass++
        Write-Host "  ok    $Name" -ForegroundColor DarkGreen
    } catch {
        $script:Fail++
        Write-Host "  FEHL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}
function Assert-Equal {
    param($Expected, $Actual, [string]$What = 'Wert')
    if ($Expected -ne $Actual) { throw ("{0}: erwartet '{1}', erhalten '{2}'" -f $What, $Expected, $Actual) }
}
function Assert-True {
    param($Condition, [string]$What = 'Bedingung')
    if (-not $Condition) { throw "$What war nicht erfuellt" }
}

# ------------------------------------------------------------------
# Ein Archiv bauen, das aussieht wie das von GitHub
# ------------------------------------------------------------------

function Baue-Archiv {
    param([string]$Version)

    $stage  = Join-Path $sandkasten ('stage-' + $Version)
    $inhalt = Join-Path $stage 'uwh-main'
    if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $inhalt -Force | Out-Null

    foreach ($n in @('uwh.ps1', 'install.ps1', 'config.yaml', 'README.md', 'LICENSE')) {
        Copy-Item (Join-Path $root $n) (Join-Path $inhalt $n)
    }
    foreach ($n in @('lib', 'scripts')) {
        Copy-Item (Join-Path $root $n) $inhalt -Recurse
    }
    New-Item -ItemType Directory -Path (Join-Path $inhalt 'profiles') -Force | Out-Null
    Copy-Item (Join-Path $root 'profiles\beispiel.yaml') (Join-Path $inhalt 'profiles\beispiel.yaml')
    Set-Content -Path (Join-Path $inhalt 'VERSION') -Value $Version -Encoding UTF8 -NoNewline

    $datei = Join-Path $sandkasten ('uwh-' + $Version + '.zip')
    Compress-Archive -Path $inhalt -DestinationPath $datei -Force

    [pscustomobject]@{ Zip = $datei; Ordner = $inhalt }
}

Write-Host ''
Write-Host 'Einrichtung' -ForegroundColor Cyan

$archiv = Baue-Archiv '0.1.0'
$ziel   = Join-Path $sandkasten 'installiert'

& (Join-Path $root 'install.ps1') -Quelle $archiv.Zip -Ziel $ziel -KeinStart -KeineVerknuepfung | Out-Null

Test-Case 'Alle Dateien kommen an' {
    foreach ($n in @('uwh.ps1', 'config.yaml', 'VERSION', 'README.md',
                     'lib\core.ps1', 'lib\menu.ps1', 'lib\update.ps1',
                     'scripts\_template.ps1', 'profiles\beispiel.yaml')) {
        Assert-True (Test-Path (Join-Path $ziel $n)) "Datei '$n'"
    }
}

Test-Case 'Keine verschachtelten Ordner' {
    foreach ($n in @('lib\lib', 'scripts\scripts', 'uwh-main')) {
        Assert-True (-not (Test-Path (Join-Path $ziel $n))) "'$n' darf es nicht geben"
    }
}

Test-Case 'Die eingerichtete Fassung laeuft' {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $aus = [string](& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ziel 'uwh.ps1') -Version -NoUpdate 2>&1)
    Assert-True ($aus -match 'uwh 0\.1\.0') "Ausgabe war '$($aus.Trim())'"
}

Test-Case 'Der Katalog ist lesbar' {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $aus = [string](& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ziel 'uwh.ps1') -List -NoUpdate 2>&1)
    Assert-True ($aus -like '*7zip*') 'ein bekannter Eintrag kommt vor'
}

Test-Case 'Ohne -KeineVerknuepfung entstuende eine Verknuepfung' {
    # Nur der Schalter wird geprueft - angelegt wird hier absichtlich keine.
    $text = Get-Content (Join-Path $root 'install.ps1') -Raw
    Assert-True ($text -match 'if \(-not \$KeineVerknuepfung\)') 'Schalter wird beachtet'
}

# ------------------------------------------------------------------
# Selbstaktualisierung
# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Selbstaktualisierung' -ForegroundColor Cyan

# Die eingerichtete Fassung laden, nicht die aus dem Arbeitsverzeichnis.
foreach ($lib in @('core', 'yaml', 'catalog', 'providers', 'menu', 'execute', 'profiles', 'update')) {
    . (Join-Path $ziel "lib\$lib.ps1")
}
function Get-UwhRoot { $ziel }

# Eigenes Profil - es muss die Aktualisierung ueberstehen.
Set-Content -Path (Join-Path $ziel 'profiles\meins.yaml') -Encoding UTF8 -Value @(
    'name: meins', 'select:', '  - 7zip')

$neu = Baue-Archiv '0.2.0'
Set-Content -Path (Join-Path $neu.Ordner 'lib\neu.ps1') -Value '# neu dazugekommen' -Encoding UTF8
Compress-Archive -Path $neu.Ordner -DestinationPath $neu.Zip -Force

$script:UwhRepoRaw = ([uri]$neu.Ordner).AbsoluteUri
$script:UwhRepoZip = ([uri]$neu.Zip).AbsoluteUri

Test-Case 'Vor der Aktualisierung steht die alte Version' {
    Assert-Equal '0.1.0' (Get-UwhLocalVersion) 'Version'
}

Test-Case 'Die neuere Version wird erkannt' {
    Assert-Equal '0.2.0' (Get-UwhRemoteVersion) 'gemeldete Version'
}

$gemacht = Update-Uwh -Quiet

Test-Case 'Die Aktualisierung wird ausgefuehrt' {
    Assert-True $gemacht 'Update-Uwh meldet Erfolg'
    Assert-Equal '0.2.0' (Get-UwhLocalVersion) 'Version angehoben'
}

Test-Case 'Neue Dateien kommen dazu' {
    Assert-True (Test-Path (Join-Path $ziel 'lib\neu.ps1')) 'lib\neu.ps1'
}

Test-Case 'Eigene Profile ueberstehen die Aktualisierung' {
    $datei = Join-Path $ziel 'profiles\meins.yaml'
    Assert-True (Test-Path $datei) 'Profil noch da'
    Assert-True ((Get-Content $datei -Raw) -like '*7zip*') 'Inhalt unveraendert'
}

Test-Case 'Auch nach der Aktualisierung keine verschachtelten Ordner' {
    Assert-True (-not (Test-Path (Join-Path $ziel 'lib\lib')))     'lib\lib'
    Assert-True (-not (Test-Path (Join-Path $ziel 'uwh-main')))    'uwh-main'
}

Test-Case 'Ein zweiter Lauf aktualisiert nicht noch einmal' {
    # Sonst wuerde sich uwh bei jedem Start im Kreis aktualisieren.
    Assert-True (-not (Update-Uwh -Quiet)) 'macht nichts mehr'
}

Test-Case 'Eine unerreichbare Quelle bleibt folgenlos' {
    $script:UwhRepoRaw = 'https://gibtesnicht.invalid/uwh'
    Assert-True ($null -eq (Get-UwhRemoteVersion)) 'keine Version gemeldet'
    Assert-True (-not (Update-Uwh -Quiet))         'keine Aktualisierung'
    Assert-Equal '0.2.0' (Get-UwhLocalVersion)     'Version unveraendert'
}

Test-Case 'Eine VERSION mit Byte-Markierung wird trotzdem gelesen' {
    # Ein unbemerkter BOM wuerde den Versionsvergleich scheitern lassen -
    # und damit die Aktualisierung stillschweigend abschalten.
    Assert-Equal '0.3.0' (ConvertTo-UwhVersionText ([char]0xFEFF + "0.3.0`r`n")) 'mit BOM'
    Assert-Equal '0.3.0' (ConvertTo-UwhVersionText ([Text.Encoding]::UTF8.GetBytes('0.3.0'))) 'als Bytes'
    Assert-Equal ''      (ConvertTo-UwhVersionText $null) 'nichts'
}

# ------------------------------------------------------------------

Remove-Item -LiteralPath $sandkasten -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("  {0} bestanden, {1} fehlgeschlagen" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''
if ($script:Fail -gt 0) { exit 1 }
exit 0
